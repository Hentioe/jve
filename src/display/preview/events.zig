const std = @import("std");
const sdl = @import("sdl");
const config = @import("config");
const gallery = @import("../../gallery.zig");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const ModKey = @import("../ModKey.zig");
const Error = @import("../errors.zig").Error;

const EventType = @FieldType(sdl.c.union_SDL_Event, "type");

pub const EventAction = union(enum) {
    none,
    mod_key: EventType,
    quit,
    toggle,
    drag_start: struct { button_x: f32, button_y: f32 },
    drag_stop: struct { button_x: f32, button_y: f32 },
    dragging: struct { xrel: f32, yrel: f32 },
    rotate: struct { key: sdl.c.SDL_Keycode },
    delete,
    scale: struct { wheel_y: f32 },
    next_or_prev: struct { wheel_y: f32 },
    reset,
};

const ActionDeps = struct {
    mod_key: *ModKey,
    dst_rect: *sdl.c.SDL_FRect,
    is_dragging: bool,
};

// 从事件中更新动作（可跨多个事件累积）
pub fn handle(event: *sdl.c.SDL_Event, action: *EventAction, state: *State) void {
    const deps: ActionDeps = .{
        .mod_key = &state.mod_key,
        .dst_rect = &state.dst_rect,
        .is_dragging = state.is_dragging,
    };
    updateActionFromEvent(action, event.*, deps);
}

// 根据动作修改状态
pub fn apply(deps: *RenderDeps, action: *const EventAction, state: *State) Error!void {
    // 其它控制常量
    const max_scale = config.get().max_scale;
    const min_scale = config.get().min_scale;
    const slide_animation = config.get().animation.image_switch; // 切换图片时是否播放侧滑自旋动画

    switch (action.*) {
        .none => {},
        .mod_key => |event_type| state.mod_key.input(event_type), // 根据类型，自动管理 Mod 按下状态
        .quit => state.running = false,
        .toggle => {
            state.running = false;
            state.toggle = true;
        },
        .drag_start => |payload| {
            state.is_dragging = true;
            std.log.info("Started dragging at mouse position: ({}, {})", .{ payload.button_x, payload.button_y });
        },
        .drag_stop => |payload| {
            state.is_dragging = false;
            state.dirty = false;
            std.log.info("Stopped dragging at mouse position: ({}, {})", .{ payload.button_x, payload.button_y });
        },
        .dragging => |payload| {
            state.move_offset.x += payload.xrel;
            state.move_offset.y += payload.yrel;
            state.dirty = true;
        },
        .rotate => |payload| if (mapKeyToAngle(payload.key)) |new_angle| state.angle.updateTargetAngular(new_angle),
        .delete => {
            // 删除当前相册图片
            std.log.info("Deleting current image: {s}", .{deps.image.file_name});
            if (gallery.deleteCurrentGetNext()) |next_image| {
                try deps.setImage(next_image);
                state.dirty = true; // 动画触发 dst_rect 更新
            } else |err| {
                if (err == gallery.Error.GalleryNoImageLeft) {
                    state.running = false; // 没有图片了，退出循环
                    std.log.info("No images left in the gallery", .{});
                } else {
                    std.log.err("Failed to delete current image: {}", .{err});
                }
            }
        },
        .scale => |payload| {
            // 处理缩放
            std.log.debug("Mouse wheel event for scaling: {d}", .{payload.wheel_y});
            if (payload.wheel_y > 0) state.scale.updateTarget(state.scale.target * 1.4) else state.scale.updateTarget(state.scale.target / 1.4);
            if (state.scale.target > max_scale) state.scale.updateTarget(max_scale) else if (state.scale.target < min_scale) state.scale.updateTarget(min_scale);
        },
        .next_or_prev => |payload| {
            // 切换图片
            std.log.debug("Mouse wheel event without modifier: {d}", .{payload.wheel_y});
            const to_next = payload.wheel_y < 0;
            if (to_next) {
                _ = gallery.next() catch |err| {
                    std.log.err("Failed to switch to next image: {}", .{err});
                };
            } else {
                _ = gallery.prev() catch |err| {
                    std.log.err("Failed to switch to previous image: {}", .{err});
                };
            }
            const crrent = gallery.current() catch |err| val: {
                std.log.err("Failed to get current image: {}", .{err});
                break :val null;
            };
            if (crrent) |new_image| {
                try deps.setImage(new_image);
            }
            if (slide_animation) {
                // 从屏幕外滑入：下一张自左侧边缘（顺时针），上一张自右侧边缘（逆时针）
                const scaled_w: f64 = @as(f64, @floatFromInt(deps.image.shape.w)) * state.scale.current;
                const window_w: f64 = @floatFromInt(deps.window.display_width);
                state.slide.startFromEdge(window_w, scaled_w, to_next);
                state.angle.reset(); // 启用切换动画时重置角度
            }
            state.dirty = true; // 触发 dst_rect 更新（禁用动画时也需要重绘新图片）
        },
        .reset => {
            // 重置所有控制参数
            state.angle.reset();
            state.scale.reset();
            state.is_dragging = false;
            state.move_offset = .{};
            state.dirty = true;
        },
    }
}

fn updateActionFromEvent(action: *EventAction, event: sdl.c.SDL_Event, deps: ActionDeps) void {
    if (event.key.key == deps.mod_key.key) {
        action.* = .{ .mod_key = event.type };
    } else if (isQuitEvent(event)) {
        action.* = .quit;
    } else if (isToggleEvent(event, deps.dst_rect)) {
        action.* = .toggle;
    } else if (isDragStartEvent(event, deps.dst_rect)) {
        action.* = .{ .drag_start = .{ .button_x = event.button.x, .button_y = event.button.y } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == sdl.c.SDL_BUTTON_LEFT) {
        action.* = .{ .drag_stop = .{ .button_x = event.button.x, .button_y = event.button.y } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_MOTION and deps.is_dragging) {
        handleDragingEvent(event, action);
    } else if (isRotateEvent(event)) {
        action.* = .{ .rotate = .{ .key = event.key.key } };
    } else if (deps.mod_key.pressedAndKeyDown(event, sdl.c.SDLK_D)) {
        action.* = .delete;
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_WHEEL and (sdl.c.SDL_GetModState() & sdl.c.SDL_KMOD_CTRL) != 0) {
        action.* = .{ .scale = .{ .wheel_y = event.wheel.y } };
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_WHEEL) {
        action.* = .{ .next_or_prev = .{ .wheel_y = event.wheel.y } };
    } else if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_SLASH) {
        action.* = .reset;
    }
}

// 是否是退出事件
fn isQuitEvent(event: sdl.c.SDL_Event) bool {
    if (event.type == sdl.c.SDL_EVENT_QUIT) { // 正常退出
        return true;
    }
    if (event.type == sdl.c.SDL_EVENT_KEY_DOWN and event.key.key == sdl.c.SDLK_ESCAPE) { // ESC 键
        return true;
    }
    return false;
}

// 是否是切换事件
fn isToggleEvent(event: sdl.c.SDL_Event, dst_rect: *sdl.c.SDL_FRect) bool {
    if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_RIGHT) { // 右键
        return true;
    } else if (event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == sdl.c.SDL_BUTTON_LEFT) { // 左键非图片区域
        return !isInRect(event, dst_rect);
    }
    return false;
}

// 是否是拖拽开始事件
fn isDragStartEvent(event: sdl.c.SDL_Event, dst_rect: *sdl.c.SDL_FRect) bool {
    const point = sdl.c.SDL_FPoint{ .x = event.button.x, .y = event.button.y };
    return event.type == sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN and
        event.button.button == sdl.c.SDL_BUTTON_LEFT and
        sdl.c.SDL_PointInRectFloat(&point, dst_rect);
}

// 方向键的数组
const DIRECTION_KEYS = [_]sdl.c.SDL_Keycode{ sdl.c.SDLK_UP, sdl.c.SDLK_DOWN, sdl.c.SDLK_LEFT, sdl.c.SDLK_RIGHT };
// 是否是旋转
fn isRotateEvent(event: sdl.c.SDL_Event) bool {
    return event.type == sdl.c.SDL_EVENT_KEY_DOWN and
        std.mem.indexOfScalar(u32, &DIRECTION_KEYS, event.key.key) != null;
}

fn handleDragingEvent(event: sdl.c.SDL_Event, action: *EventAction) void {
    switch (action.*) {
        .dragging => |*payload| {
            // 如果这一帧里已经有 dragging 动作了，累加位移
            payload.xrel += event.motion.xrel;
            payload.yrel += event.motion.yrel;
        },
        .drag_stop => {}, // 鼠标松开时，可能残留移动事件，避免覆盖 drag_stop
        else => {
            action.* = .{ .dragging = .{ .xrel = event.motion.xrel, .yrel = event.motion.yrel } };
        },
    }
}

// 按键映射旋转角度
fn mapKeyToAngle(key: sdl.c.SDL_Keycode) ?f64 {
    return switch (key) {
        sdl.c.SDLK_UP => 0.0,
        sdl.c.SDLK_DOWN => 180.0,
        sdl.c.SDLK_LEFT => 270.0,
        sdl.c.SDLK_RIGHT => 90.0,
        else => null,
    };
}

// 判断鼠标位置是否在图片上
fn isInRect(event: sdl.c.SDL_Event, dst_rect: *sdl.c.SDL_FRect) bool {
    const mouse_x = event.button.x;
    const mouse_y = event.button.y;
    return mouse_x >= dst_rect.x and mouse_x <= dst_rect.x + dst_rect.w and
        mouse_y >= dst_rect.y and mouse_y <= dst_rect.y + dst_rect.h;
}
