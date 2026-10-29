const std = @import("std");
const sdl = @import("sdl");
const Key = sdl.Key;
const ui = @import("../../ui.zig");
const tasks = @import("tasks.zig");
const RenderDeps = @import("RenderDeps.zig");
const extractor = @import("../../extractor.zig");
const State = @import("State.zig");
const Error = @import("../errors.zig").Error;

pub const UIHandler = struct {
    deps: *RenderDeps,
    title_bar: *?ui.TitleBar,
    state: *State = undefined,

    const Self = @This();

    pub fn init(deps: *RenderDeps, title_bar: *?ui.TitleBar) Self {
        return Self{
            .deps = deps,
            .title_bar = title_bar,
        };
    }

    /// 绑定事件
    pub fn bindEvents(self: *Self, state: *State) void {
        self.state = state;
        if (self.title_bar.*) |*title_bar| {
            title_bar.on_close = ui.Event.Callback(void).bind(self, Self.close);
            title_bar.on_minimize = ui.Event.Callback(void).bind(self, Self.minimize);
            title_bar.on_button_hover = ui.Event.Callback(bool).bind(self, Self.titleBarButtonHover);
        }
    }

    pub fn titleBarButtonHover(self: *Self, is_hover: bool) void {
        std.log.debug("Title bar button hover state changed: {any}", .{is_hover});
        self.deps.window.is_draggable = !is_hover; // 当鼠标悬停在标题栏按钮上时，窗口不可拖动（避免丢失点击事件）
    }

    pub fn close(self: *Self, _: void) void {
        std.log.debug("Close button clicked", .{});
        self.state.running = false;
    }

    pub fn minimize(self: *Self, _: void) void {
        std.log.debug("Minimize button clicked", .{});
        self.deps.window.minimize() catch |err| std.log.err("Failed to minimize window: {s}", .{@errorName(err)});
    }
};

const slide_sensitivity = 100; // 横向滑动灵敏度

pub const EventAction = union(enum) {
    none,
    quit,
    minimize,
    restored,
    toggle,
    reset,
    invert,
    grayscale,
    save_screenshot: struct { include_bg: bool },
    copy_screenshot,
    start_task,
    toggle_custom_shader,
    change_playing: bool,
    slide_start: struct { button: u8 },
    slide_stop: struct { button: u8 },
    sliding: struct { xrel: f32 },
    channel_change: i32,
    marker: struct { x: f32, y: f32 },
};

pub const Handler = struct {
    const Self = @This();

    deps: *RenderDeps,
    state: *State,
    action: EventAction = .none,
    task_sched: *tasks.Scheduler,

    pub fn handle(self: *Self, event: *const sdl.Event) void {
        // 分发 ui 事件给所有 widget
        if (ui.Event.fromSdl(event)) |ui_event| for (self.deps.widgets) |*w| w.event(&ui_event);
        // 更新修饰键状态（在动作更新之前）
        self.state.modifiers.input(event);
        // 更新动作
        self.updateAction(event);
        // 处理绑定的事件（如果有会跳过后续事件处理）
        if (self.handleBinding(event)) return;
        // 检查修饰键状态变化
        if (self.state.modifiers.takePrimaryPressedChanged()) { // 如果主修饰键按下状态发生变化
            self.deps.window.is_draggable = !self.state.modifiers.primaryPressed(); // 窗口在主 mod 未按下时才能拖动
        }
    }

    pub fn apply(self: *Self) Error!void {
        const deps = self.deps;
        const state = self.state;

        switch (self.action) {
            .none => {},
            .quit => state.running = false,
            .minimize => {
                if (deps.animation != null) state.playback.setPlaying(sdl.getTicks(), false); // 暂停动图播放
            },
            .restored => {
                if (deps.animation != null) state.playback.setPlaying(sdl.getTicks(), true); // 恢复动图播放
            },
            .toggle => {
                state.toggle = true;
                state.running = false;
            },
            .invert => state.is_inverted = !state.is_inverted,
            .grayscale => state.is_grayscale = !state.is_grayscale,
            .save_screenshot => |payload| {
                state.screenshot.action = .save;
                state.screenshot.include_bg = payload.include_bg;
            },
            .copy_screenshot => state.screenshot.action = .copy,
            .start_task => {
                if (!state.is_busy) {
                    // 点击区域需要转换回原图坐标
                    const click = if (state.marker_pos) |p| try deps.window.toImagePoint(p.x, p.y) else null;
                    // 纹理提取必须在循环线程完成，避免任务线程访问已失效的 GPU 资源
                    var extracted = extractor.extract(deps.allocator, deps.device, state.tex_src, deps.image.shape.to(u32)) catch |err| {
                        std.log.err("Failed to extract texture for task: {}", .{err});
                        try state.showError(deps, "任务出错：{s}", .{@errorName(err)});
                        return;
                    };
                    self.task_sched.launch(.remove_bg, .{ .remover = .{
                        deps.allocator,
                        extracted,
                        click,
                    } }) catch |err| {
                        std.log.err("Failed to start task: {}", .{err});
                        extracted.deinit(); // 任务未启动，释放已提取的数据
                        try state.showError(deps, "任务出错：{s}", .{@errorName(err)});
                        return;
                    };
                    std.log.info("Task started successfully", .{});
                    state.is_busy = true;
                    if (deps.animation != null) state.playback.setPlaying(sdl.getTicks(), false); // 暂停动图播放
                }
            },
            .toggle_custom_shader => self.state.custom_shader_enabled = !self.state.custom_shader_enabled,
            .change_playing => |is_playing| if (deps.animation != null) state.playback.setPlaying(sdl.getTicks(), is_playing),
            .slide_start => |payload| {
                state.is_sliding = true;
                std.log.debug("Mouse wheel event down: {}", .{payload.button});
            },
            .slide_stop => |payload| {
                state.is_sliding = false;
                std.log.debug("Mouse wheel event up: {}", .{payload.button});
            },
            .sliding => |payload| {
                state.slide_value += payload.xrel / slide_sensitivity;
                std.log.debug("Horizontal value updated: {}", .{state.slide_value});
            },
            .channel_change => |channel| {
                state.channel = channel;
                std.log.debug("Channel changed to: {}", .{state.channel});
            },
            .marker => |payload| {
                var removed = false;
                if (state.marker_pos) |prev| {
                    const dx = payload.x - prev.x;
                    const dy = payload.y - prev.y;
                    // 二次点击落在标记范围内，则移除标记
                    if (dx * dx + dy * dy <= State.MARKER_RADIUS * State.MARKER_RADIUS) {
                        state.marker_pos = null;
                        removed = true;
                        std.log.debug("Marker removed", .{});
                    }
                }
                if (!removed) {
                    state.marker_pos = .{ .x = payload.x, .y = payload.y };
                    std.log.debug("Marker position updated: ({}, {})", .{ payload.x, payload.y });
                }
            },
            .reset => {
                state.is_inverted = false;
                state.is_grayscale = false;
                state.brightness = 0;
                state.contrast = 1;
                state.gamma = 1;
                state.slide_value = 0;
                state.marker_pos = null;
                state.custom_shader_enabled = false;
                state.manual = null;
                if (state.tex_mask) |tex| { // 移除遮罩
                    deps.device.releaseGPUTexture(tex);
                    state.tex_mask = null;
                }
            },
        }
    }

    fn updateAction(self: *Self, event: *const sdl.Event) void {
        const action_ptr = &self.action;
        const modifiers = &self.state.modifiers;
        const is_sliding = self.state.is_sliding;
        const is_busy = self.state.is_busy;
        const is_playing = self.state.playback.playing;

        if (event.type == sdl.EVENT_QUIT) {
            action_ptr.* = .quit;
        } else if (event.type == sdl.EVENT_WINDOW_MINIMIZED) {
            action_ptr.* = .minimize;
        } else if (event.type == sdl.EVENT_WINDOW_RESTORED) {
            action_ptr.* = .restored;
        } else if (isToggleEvent(event)) {
            action_ptr.* = .toggle;
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.slash.matches(event.key.key)) { // / 键重置所有参数
            action_ptr.* = .reset;
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.r.matches(event.key.key) and !modifiers.primaryPressed()) { // R 键反转颜色
            action_ptr.* = .invert;
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.g.matches(event.key.key)) { // G 键灰阶化
            action_ptr.* = .grayscale;
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.s.matches(event.key.key)) { // S 键保存截图（如果按下 Mod 键，则包含背景）
            action_ptr.* = .{ .save_screenshot = .{ .include_bg = modifiers.primaryPressed() } };
        } else if (modifiers.primaryPressedBoth(event, Key.r) and !is_busy) { // Mod+R 去除背景
            action_ptr.* = .start_task;
        } else if (modifiers.primaryPressedBoth(event, Key.t)) { // Mod+T 切换自定义着色器的启用状态
            action_ptr.* = .toggle_custom_shader;
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.space.matches(event.key.key) and !is_busy) { // 空格键暂停/播放动画（繁忙时禁止控制）
            action_ptr.* = .{ .change_playing = !is_playing };
        } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.c.matches(event.key.key) and (event.key.mod & sdl.c.SDL_KMOD_CTRL) != 0) { // Ctrl+C 复制截图
            action_ptr.* = .copy_screenshot;
        } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节开始
            action_ptr.* = .{ .slide_start = .{ .button = event.button.button } };
        } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节结束
            action_ptr.* = .{ .slide_stop = .{ .button = event.button.button } };
        } else if (event.type == sdl.c.SDL_EVENT_MOUSE_MOTION and is_sliding) { // 滑动中
            handleSlidingEvent(event, action_ptr);
        } else if (isChannelChangeEvent(event)) {
            if (mapKeyToChannel(event.key.key)) |channel| action_ptr.* = .{ .channel_change = channel };
        } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_LEFT and modifiers.primaryPressed()) { // Mod + 鼠标左键单击，获取位置
            action_ptr.* = .{ .marker = .{ .x = event.button.x, .y = event.button.y } };
        }
    }

    // 处理按键绑定事件
    fn handleBinding(ctx: *Handler, event: *const sdl.Event) bool {
        var iter = ctx.deps.manuals.keyIterator();
        while (iter.next()) |item| if (item.*.keybinding) |binding| {
            var matched = false;
            if (event.type == sdl.EVENT_KEY_DOWN and binding.key.matches(event.key.key)) {
                matched = if (binding.modifier) |modifier| ctx.state.modifiers.working(modifier) else true;
            }

            if (matched) if (ctx.deps.manuals.get(item.*)) |pl| {
                ctx.state.manual = if (ctx.state.manual == null or ctx.state.manual != pl) pl else null;
                return true;
            };
        };
        return false;
    }

    pub fn screenshot(ctx: *Handler) Error!void {
        if (ctx.state.screenshot.action == .none) return;
        ctx.state.screenshot.running = true;
        const task: tasks.Name = if (ctx.state.screenshot.action == .save) .save_screenshot else .copy_screenshot;
        ctx.task_sched.launch(task, .{ .screenshot = .{
            ctx.deps.allocator,
            ctx.deps.device,
            ctx.state.tex_src,
            &ctx.deps.image,
        } }) catch |err| {
            ctx.state.screenshot = .default;
            try ctx.state.showError(ctx.deps, "截图失败：{s}", .{@errorName(err)});
        };
    }
};

// 是否是切换事件
fn isToggleEvent(event: *const sdl.Event) bool {
    return event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_RIGHT; // 右键
}

fn isChannelChangeEvent(event: *const sdl.Event) bool {
    if ((event.key.mod & sdl.c.SDL_KMOD_RALT) == 0) return false; // 判断右 alt 是否按下
    return Key._0.matches(event.key.key) or
        Key._1.matches(event.key.key) or
        Key._2.matches(event.key.key) or
        Key._3.matches(event.key.key) or
        Key._4.matches(event.key.key);
}

fn mapKeyToChannel(key: sdl.c.SDL_Keycode) ?u8 {
    return switch (Key.from(key) orelse return null) {
        ._0 => 0,
        ._1 => 1,
        ._2 => 2,
        ._3 => 3,
        ._4 => 4,
        else => null,
    };
}

fn handleSlidingEvent(event: *const sdl.Event, action: *EventAction) void {
    switch (action.*) {
        .sliding => |*payload| {
            // 如果这一帧里已经有 sliding 动作了，累加位移
            payload.xrel += event.motion.xrel;
        },
        .slide_stop => {}, // 中键松开时，可能残留滑动事件，避免覆盖 slide_stop
        else => {
            action.* = .{ .sliding = .{ .xrel = event.motion.xrel } };
        },
    }
}
