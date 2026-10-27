const std = @import("std");
const sdl = @import("sdl");
const Key = sdl.Key;
const ui = @import("../../ui.zig");
const RenderDeps = @import("RenderDeps.zig");
const Task = @import("../Task.zig");
const Modifiers = @import("../Modifiers.zig");
const Device = @import("../../Device.zig");
const Size2D = @import("shared").Size2D;
const State = @import("State.zig");
const Screenshot = @import("../../Screenshot.zig");
const Error = @import("../errors.zig").Error;

pub const Context = struct {
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

const ActionDeps = struct {
    modifiers: *Modifiers,
    is_sliding: bool,
    is_busy: bool,
    is_playing: bool,
};

/// 检查和处理后台任务，失败会在横幅显示错误消息。
pub fn checkHandleTask(deps: *RenderDeps, state: *State) Error!void {
    if (state.task) |t| if (t.poll() == .done) {
        defer {
            t.finish();
            state.task = null;
            state.is_busy = false;
            state.dirty = false;
        }
        if (t.result) |*res| switch (res.*) {
            .success => |s| {
                std.log.info("Task result is reading...", .{});
                const mask_ptr = s.data_ptr; // 获取遮罩数据指针
                const mask_size: Size2D(u32) = .{ .w = s.width, .h = s.height };
                const uploader = try Device.getUploader();
                const new_mask = try uploader.uploadTextureBorrowed(&deps.offscreen_info, mask_ptr, mask_size);
                try uploader.submit();
                if (state.tex_mask) |tex| deps.device.releaseGPUTexture(tex); // 释放旧遮罩纹理
                state.tex_mask = new_mask;
                std.log.info("Task result read complete", .{});
            },
            .failure => |err| try state.showError(deps, "任务出错：{s}", .{@errorName(err)}),
        };
    };
}

/// 处理截图相关事件
pub fn handleScreenshot(deps: *RenderDeps, state: *State) Error!void {
    // 创建截图器
    var s = Screenshot.init(deps.allocator, deps.device, state.tex_src, &deps.image) catch |err| {
        try state.showError(deps, "截图失败：{s}", .{@errorName(err)});
        return;
    };

    defer s.deinit();
    const action = state.screenshot.action;
    if (action == .save) s.saveToFile() catch |err| try state.showError(deps, "保存失败：{s}", .{@errorName(err)});
    if (action == .copy) s.copyToClipboard();

    // 重置截图输入
    state.screenshot = .default;
}

/// 处理按键绑定事件
fn handleBinding(event: *const sdl.Event, deps: *const RenderDeps, state: *State) bool {
    var iter = deps.manuals.keyIterator();
    while (iter.next()) |item| if (item.*.keybinding) |binding| {
        var matched = false;
        if (event.type == sdl.EVENT_KEY_DOWN and binding.key.matches(event.key.key)) {
            matched = if (binding.modifier) |modifier| state.modifiers.working(modifier) else true;
        }

        if (matched) if (deps.manuals.get(item.*)) |pl| {
            state.manual = if (state.manual == null or state.manual != pl) pl else null;
            return true;
        };
    };
    return false;
}

// 从事件中更新动作（可跨多个事件累积）
pub fn handle(event: *const sdl.Event, action: *EventAction, deps: *RenderDeps, state: *State) void {
    if (handleBinding(event, deps, state)) return; // 绑定的事件触发，直接跳过后续事件处理
    const action_deps: ActionDeps = .{
        .modifiers = &state.modifiers,
        .is_sliding = state.is_sliding,
        .is_busy = state.is_busy,
        .is_playing = state.playback.playing,
    };
    state.modifiers.input(event); // 更新修饰键状态（在动作更新之前）
    updateAction(action, event.*, action_deps); // 更新动作
    if (state.modifiers.takePrimaryPressedChanged()) { // 如果主修饰键按下状态发生变化
        deps.window.is_draggable = !state.modifiers.primaryPressed(); // 窗口在主 mod 未按下时才能拖动
    }
}

/// 根据动作修改状态。
pub fn applyAction(action: EventAction, deps: *const RenderDeps, state: *State) Error!void {
    switch (action) {
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
            if (state.task == null) {
                state.is_busy = true;
                // 点击区域需要转换回原图坐标
                const click = if (state.marker_pos) |p| try deps.window.toImagePoint(p.x, p.y) else null;
                if (Task.start(deps.allocator, deps.device, state.tex_src, .{ .shape = deps.image.shape, .click = click })) |t| {
                    std.log.info("Task started successfully", .{});
                    state.task = t;
                    if (deps.animation != null) state.playback.setPlaying(sdl.getTicks(), false); // 暂停动图播放
                } else |err| {
                    std.log.err("Failed to start task: {}", .{err});
                    state.is_busy = false;
                }
            }
        },
        .toggle_custom_shader => state.custom_shader_enabled = !state.custom_shader_enabled,
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

fn updateAction(ptr: *EventAction, event: sdl.Event, deps: ActionDeps) void {
    if (event.type == sdl.EVENT_QUIT) {
        ptr.* = .quit;
    } else if (event.type == sdl.EVENT_WINDOW_MINIMIZED) {
        ptr.* = .minimize;
    } else if (event.type == sdl.EVENT_WINDOW_RESTORED) {
        ptr.* = .restored;
    } else if (isToggleEvent(event)) {
        ptr.* = .toggle;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.slash.matches(event.key.key)) { // / 键重置所有参数
        ptr.* = .reset;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.r.matches(event.key.key) and !deps.modifiers.primaryPressed()) { // R 键反转颜色
        ptr.* = .invert;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.g.matches(event.key.key)) { // G 键灰阶化
        ptr.* = .grayscale;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.s.matches(event.key.key)) { // S 键保存截图（如果按下 Mod 键，则包含背景）
        ptr.* = .{ .save_screenshot = .{ .include_bg = deps.modifiers.primaryPressed() } };
    } else if (deps.modifiers.primaryPressedBoth(event, Key.r) and !deps.is_busy) { // Mod+R 去除背景
        ptr.* = .start_task;
    } else if (deps.modifiers.primaryPressedBoth(event, Key.t)) { // Mod+T 切换自定义着色器的启用状态
        ptr.* = .toggle_custom_shader;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.space.matches(event.key.key) and !deps.is_busy) { // 空格键暂停/播放动画（繁忙时禁止控制）
        ptr.* = .{ .change_playing = !deps.is_playing };
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and Key.c.matches(event.key.key) and (event.key.mod & sdl.c.SDL_KMOD_CTRL) != 0) { // Ctrl+C 复制截图
        ptr.* = .copy_screenshot;
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节开始
        ptr.* = .{ .slide_start = .{ .button = event.button.button } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节结束
        ptr.* = .{ .slide_stop = .{ .button = event.button.button } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_MOTION and deps.is_sliding) { // 滑动中
        handleSlidingEvent(event, ptr);
    } else if (isChannelChangeEvent(event)) {
        if (mapKeyToChannel(event.key.key)) |channel| ptr.* = .{ .channel_change = channel };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_LEFT and deps.modifiers.primaryPressed()) { // Mod + 鼠标左键单击，获取位置
        ptr.* = .{ .marker = .{ .x = event.button.x, .y = event.button.y } };
    }
}

// 是否是切换事件
fn isToggleEvent(event: sdl.c.SDL_Event) bool {
    return event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_RIGHT; // 右键
}

fn isChannelChangeEvent(event: sdl.c.SDL_Event) bool {
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

fn handleSlidingEvent(event: sdl.c.SDL_Event, action: *EventAction) void {
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
