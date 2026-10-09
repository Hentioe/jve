const std = @import("std");
const sdl = @import("sdl");
const Task = @import("../Task.zig");
const ModKey = @import("../ModKey.zig");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const Error = @import("../errors.zig").Error;

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
    marker: struct { x: f32, y: f32 },
};

const ActionDeps = struct {
    mod_key: *ModKey,
    is_sliding: bool,
    is_busy: bool,
};

// 从事件中更新动作（可跨多个事件累积）
pub fn handle(event: *sdl.c.SDL_Event, action: *EventAction, state: *State) void {
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
            deps.window.mod_key_pressed = state.mod_key.pressed; // 更新窗口的 Mod 键按下状态
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
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_LEFT) { // 鼠标左键单击，获取位置
        action.* = .{ .marker = .{ .x = event.button.x, .y = event.button.y } };
    }
}

// 是否是切换事件
fn isToggleEvent(event: sdl.c.SDL_Event) bool {
    return event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_RIGHT; // 右键
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
