const std = @import("std");
const sdl = @import("sdl");
const Task = @import("../Task.zig");
const ModKey = @import("../ModKey.zig");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const ui = @import("../../ui.zig");
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
        self.deps.window.minimize() catch |err| std.log.err("Failed to minimize window: {any}", .{err});
    }
};

const EventType = @FieldType(sdl.c.union_SDL_Event, "type");
const slide_sensitivity = 100; // 横向滑动灵敏度

pub const EventAction = union(enum) {
    none,
    quit,
    toggle,
    mod_key: EventType,
    reset,
    invert,
    grayscale,
    save_screenshot,
    copy_screenshot,
    start_task,
    toggle_custom_shader,
    slide_start: struct { button: u8 },
    slide_stop: struct { button: u8 },
    sliding: struct { xrel: f32 },
    channel_change: i32,
    marker: struct { x: f32, y: f32 },
};

const ActionDeps = struct {
    mod_key: *ModKey,
    is_sliding: bool,
    is_busy: bool,
};

// 从事件中更新动作（可跨多个事件累积）
pub fn handle(event: *sdl.Event, action: *EventAction, state: *State) void {
    const deps: ActionDeps = .{
        .mod_key = &state.mod_key,
        .is_sliding = state.is_sliding,
        .is_busy = state.is_busy,
    };
    updateActionFromEvent(action, event.*, deps);
}

// 根据动作修改状态
pub fn apply(deps: *RenderDeps, action: *const EventAction, state: *State) Error!void {
    switch (action.*) {
        .none => {},
        .quit => state.running = false,
        .toggle => {
            state.toggle = true;
            state.running = false;
        },
        .mod_key => |event_type| {
            state.mod_key.input(event_type); // 根据类型，自动管理按下状态
            deps.window.is_draggable = !state.mod_key.pressed; // Mod 键盘没有按下时才能拖动
        },
        .invert => state.is_inverted = !state.is_inverted,
        .grayscale => state.is_grayscale = !state.is_grayscale,
        .save_screenshot => state.save_screenshot = true,
        .copy_screenshot => state.copy_screenshot = true,
        .start_task => {
            if (state.task == null) {
                state.is_busy = true;
                // 点击区域需要转换回原图坐标
                const click = if (state.marker_pos) |p| try deps.window.toImagePoint(p.x, p.y) else null;
                if (Task.start(deps.allocator, deps.device, state.tex_src, .{ .shape = deps.image.shape, .click = click })) |t| {
                    std.log.info("Task started successfully", .{});
                    state.task = t;
                } else |err| {
                    std.log.err("Failed to start task: {}", .{err});
                    state.is_busy = false;
                }
            }
        },
        .toggle_custom_shader => state.custom_shader_enabled = !state.custom_shader_enabled,
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
                if (dx * dx + dy * dy <= State.marker_radius * State.marker_radius) {
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
            if (state.tex_mask) |tex| { // 移除遮罩
                deps.device.releaseGPUTexture(tex);
                state.tex_mask = null;
            }
        },
    }
}

fn updateActionFromEvent(action: *EventAction, event: sdl.c.SDL_Event, deps: ActionDeps) void {
    if (event.type == sdl.c.SDL_EVENT_QUIT) {
        action.* = .quit;
    } else if (isToggleEvent(event)) {
        action.* = .toggle;
    } else if (event.key.key == deps.mod_key.key) {
        action.* = .{ .mod_key = event.type };
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_SLASH) { // / 键重置所有参数
        action.* = .reset;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_R and !deps.mod_key.pressed) { // R 键反转颜色
        action.* = .invert;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_G) { // G 键灰阶化
        action.* = .grayscale;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_S) { // S 键保存截图
        action.* = .save_screenshot;
    } else if (deps.mod_key.pressedAndKeyDown(event, sdl.c.SDLK_R) and !deps.is_busy) { // Mod+R 去除背景
        action.* = .start_task;
    } else if (deps.mod_key.pressedAndKeyDown(event, sdl.c.SDLK_T)) { // Mod+T 切换自定义着色器的启用状态
        action.* = .toggle_custom_shader;
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_C and (event.key.mod & sdl.c.SDL_KMOD_CTRL) != 0) { // Ctrl+C 复制截图
        action.* = .copy_screenshot;
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节开始
        action.* = .{ .slide_start = .{ .button = event.button.button } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == sdl.c.SDL_BUTTON_MIDDLE) { // 横向调节结束
        action.* = .{ .slide_stop = .{ .button = event.button.button } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_MOTION and deps.is_sliding) { // 滑动中
        handleSlidingEvent(event, action);
    } else if (isChannelChangeEvent(event)) {
        if (mapKeyToChannel(event.key.key)) |channel| action.* = .{ .channel_change = channel };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_LEFT and deps.mod_key.pressed) { // Mod + 鼠标左键单击，获取位置
        action.* = .{ .marker = .{ .x = event.button.x, .y = event.button.y } };
    }
}

// 是否是切换事件
fn isToggleEvent(event: sdl.c.SDL_Event) bool {
    return event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_RIGHT; // 右键
}

fn isChannelChangeEvent(event: sdl.c.SDL_Event) bool {
    if ((event.key.mod & sdl.c.SDL_KMOD_RALT) == 0) return false; // 判断右 alt 是否按下
    return event.key.key == sdl.c.SDLK_0 or
        event.key.key == sdl.c.SDLK_1 or
        event.key.key == sdl.c.SDLK_2 or
        event.key.key == sdl.c.SDLK_3 or
        event.key.key == sdl.c.SDLK_4;
}

fn mapKeyToChannel(key: sdl.c.SDL_Keycode) ?u8 {
    return switch (key) {
        sdl.c.SDLK_0 => 0,
        sdl.c.SDLK_1 => 1,
        sdl.c.SDLK_2 => 2,
        sdl.c.SDLK_3 => 3,
        sdl.c.SDLK_4 => 4,
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
