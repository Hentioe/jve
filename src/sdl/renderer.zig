const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const root = @import("../root.zig");
const shared = @import("shared");
const config = @import("config");
const gallery = root.gallery;
const Error = @import("errors.zig").Error;
const State = @import("State.zig");
const Window = @import("window.zig");
const LImage = @import("vips").LImage;
const ModKey = @import("ModKey.zig");
const Animated = @import("Animated.zig");
const SlideIn = @import("SlideIn.zig");
const Delta = @import("Delta.zig");
const ISize = shared.ISize;
const Point = shared.Point(f32);
const RenderNext = @import("enums.zig").RenderNext;

const EventType = @FieldType(c.union_SDL_Event, "type");
const EventAction = union(enum) {
    none,
    mod_key: EventType,
    quit,
    toggle,
    drag_start: struct { button_x: f32, button_y: f32 },
    drag_stop: struct { button_x: f32, button_y: f32 },
    dragging: struct { xrel: f32, yrel: f32 },
    rotate: struct { key: c.SDL_Keycode },
    delete,
    scale: struct { wheel_y: f32 },
    next_or_prev: struct { wheel_y: f32 },
    reset,
};

// 基于 sdl_renderer 渲染图片
pub fn render(_: std.mem.Allocator, state: *State) Error!RenderNext {
    var image = try gallery.current();
    // 更新状态
    try state.startRendering(&image, .sdl_renderer);
    // 创建窗口
    var window = state.window.?; // 确保在 startRendering 中完成初始化
    // 更新窗口标题
    try window.setTitle(image.file_name);
    // 创建渲染器
    const renderer = state.renderer.?;
    // 创建纹理（先尝试从缓存中读取）
    var texture = try state.readTexture(renderer);
    if (texture == null) { // 没有就创建新的纹理
        texture = try createTexture(renderer, &image);
    } else {
        // 复用纹理
        std.log.info("Reusing texture from state", .{});
    }
    errdefer c.SDL_DestroyTexture(texture);
    // 创建目标矩形
    var dst_rect = c.SDL_FRect{};
    calculateDstRect(&dst_rect, window, image.shape.toISize(i32), .{});
    // 循环、动画和事件参数
    var event: c.SDL_Event = undefined;
    var action: EventAction = .none;
    var running = true;
    var toggle = false;
    var dirty = true;
    var delta = Delta.init(); // 帧间隔计时器
    // 其它控制常量
    const max_scale = config.get().max_scale;
    const min_scale = config.get().min_scale;
    const slide_animation = config.get().animation.image_switch; // 切换图片时是否播放侧滑自旋动画；为 false 则原位直接替换
    // 其它控制参数
    var mod_key = ModKey.init(ModKey.keycode(config.modKey())); // Mod 键
    var is_dragging: bool = false; // 是否正在拖动
    var move_offset = state.move_offset; // 移动偏移量
    var scale = Animated.init(1.0, 1.0, 15); // 缩放
    scale.updateTarget(state.target_scale); // 更新为缓存的缩放目标值
    var angle = Animated.init(0.0, 0.0, 15); // 角度
    angle.updateTarget(state.target_angle); // 更新为缓存的角度目标值
    var slide = SlideIn.init(1.0, 20.0, 1.0); // 切换图片时的侧滑自旋
    while (running) {
        // 计算 delta
        delta.update();
        // std.log.info("delta: {}, fps: {}", .{ delta.value, delta.fps });
        defer action = .none; // 重置动作
        // 动作的依赖项
        const action_deps: ActionDeps = .{
            .mod_key = &mod_key,
            .dst_rect = &dst_rect,
            .is_dragging = is_dragging,
        };
        if (!dirty) {
            var wait_event: c.SDL_Event = undefined;
            if (c.SDL_WaitEvent(&wait_event)) updateActionFromEvent(&action, wait_event, action_deps);
            delta.reset(); // 重置 delta（否则阻塞后唤醒会计算出巨大的 delta 值）
        }
        // 从事件中更新动作
        while (c.SDL_PollEvent(&event)) updateActionFromEvent(&action, event, action_deps);

        // 根据动作修改状态
        switch (action) {
            .none => {},
            .mod_key => |event_type| mod_key.input(event_type), // 根据类型，自动管理 Mod 按下状态
            .quit => running = false,
            .toggle => {
                running = false;
                toggle = true;
            },
            .drag_start => |payload| {
                is_dragging = true;
                std.log.info("Started dragging at mouse position: ({}, {})", .{ payload.button_x, payload.button_y });
            },
            .drag_stop => |payload| {
                is_dragging = false;
                dirty = false;
                std.log.info("Stopped dragging at mouse position: ({}, {})", .{ payload.button_x, payload.button_y });
            },
            .dragging => |payload| {
                move_offset.x += payload.xrel;
                move_offset.y += payload.yrel;
                dirty = true;
            },
            .rotate => |payload| if (mapKeyToAngle(payload.key)) |new_angle| angle.updateTarget(new_angle),
            .delete => {
                // 删除当前相册图片
                std.log.info("Deleting current image: {s}", .{image.file_name});
                if (gallery.deleteCurrentGetNext()) |next_image| {
                    image = next_image;
                    c.SDL_DestroyTexture(texture);
                    texture = try createTexture(renderer, &next_image);
                    dirty = true; // 动画触发 dst_rect 更新
                } else |err| {
                    if (err == gallery.Error.GalleryNoImageLeft) {
                        running = false; // 没有图片了，退出循环
                        std.log.info("No images left in the gallery", .{});
                    } else {
                        std.log.err("Failed to delete current image: {}", .{err});
                    }
                }
            },
            .scale => |payload| {
                // 处理缩放
                std.log.debug("Mouse wheel event for scaling: {d}", .{payload.wheel_y});
                if (payload.wheel_y > 0) scale.updateTarget(scale.target * 1.4) else scale.updateTarget(scale.target / 1.4);
                if (scale.target > max_scale) scale.updateTarget(max_scale) else if (scale.target < min_scale) scale.updateTarget(min_scale);
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
                    image = new_image;
                    c.SDL_DestroyTexture(texture);
                    texture = try createTexture(renderer, &new_image);
                }
                if (slide_animation) {
                    // 从屏幕外滑入：下一张自左侧边缘（顺时针），上一张自右侧边缘（逆时针）
                    const scaled_w: f64 = @as(f64, @floatFromInt(image.shape.w)) * scale.current;
                    const window_w: f64 = @floatFromInt(window.display_width);
                    slide.startFromEdge(window_w, scaled_w, to_next);
                    angle.reset(); // 启用切换动画时重置角度
                }
                dirty = true; // 触发 dst_rect 更新（禁用动画时也需要重绘新图片）
            },
            .reset => {
                // 重置所有控制参数
                angle.reset();
                scale.reset();
                is_dragging = false;
                move_offset = .{};
                dirty = true;
            },
        }

        // 根据状态执行渲染
        if (dirty or scale.state == .running or angle.state == .running or slide.isRunning()) {
            if (scale.state == .running) {
                if (scale.isNearFinished()) {
                    std.log.debug("Scale is near finished, diff: {d}", .{scale.target - scale.current});
                    scale.finish();
                } else {
                    scale.nextStep(delta.value);
                }
                std.log.debug("current_scale: {d}, target_scale: {d}, diff: {d}", .{ scale.current, scale.target, scale.target - scale.current });
            }
            if (angle.state == .running) {
                if (angle.isNearFinished()) {
                    std.log.debug("Angle is near finished, diff: {d}", .{angle.target - angle.current});
                    angle.finish();
                } else {
                    angle.nextStep(delta.value);
                }
            }
            if (slide.isRunning()) {
                slide.nextStep(delta.value);
            }
            dirty = scale.state == .running or angle.state == .running or slide.isRunning(); // 如果没有动画了，表示渲染干净了
            // 计算尺寸
            const f_size = image.shape.toISize(f32);
            const new_size: ISize(i32) = .{ .w = @intFromFloat(f_size.w * scale.current), .h = @intFromFloat(f_size.h * scale.current) };
            const slide_offset = Point{ .x = move_offset.x + @as(f32, @floatCast(slide.offset)), .y = move_offset.y };
            calculateDstRect(&dst_rect, window, new_size, slide_offset);
            window.imageSizeUpdated(image.shape.toISize(i32));
        }
        const render_angle: f64 = if (slide.isRunning()) slide.angle else angle.current;
        const alpha: u8 = if (window.windowed) 255 else 60; // 根据边框模式设置背景透明度
        check(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, alpha)); // 设置白色背景
        check(c.SDL_RenderClear(renderer));
        check(c.SDL_RenderTextureRotated(renderer, texture, null, &dst_rect, render_angle, null, c.SDL_FLIP_NONE));
        check(c.SDL_RenderPresent(renderer));
    }
    // 缓存控制参数
    state.target_angle = angle.target;
    state.target_scale = scale.target;
    state.move_offset = move_offset;
    // 通知状态停止渲染
    try state.stopRendering();

    return if (toggle) .toggle else .quit;
}

const ActionDeps = struct {
    mod_key: *ModKey,
    dst_rect: *c.SDL_FRect,
    is_dragging: bool,
};

fn updateActionFromEvent(action: *EventAction, event: c.SDL_Event, deps: ActionDeps) void {
    if (event.key.key == deps.mod_key.key) {
        action.* = .{ .mod_key = event.type };
    } else if (isQuitEvent(event)) {
        action.* = .quit;
    } else if (isToggleEvent(event, deps.dst_rect)) {
        action.* = .toggle;
    } else if (isDragStartEvent(event, deps.dst_rect)) {
        action.* = .{ .drag_start = .{ .button_x = event.button.x, .button_y = event.button.y } };
    } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == c.SDL_BUTTON_LEFT) {
        action.* = .{ .drag_stop = .{ .button_x = event.button.x, .button_y = event.button.y } };
    } else if (event.type == c.SDL_EVENT_MOUSE_MOTION and deps.is_dragging) {
        handleDragingEvent(event, action);
    } else if (isRotateEvent(event)) {
        action.* = .{ .rotate = .{ .key = event.key.key } };
    } else if (deps.mod_key.pressedAndKeyDown(event, c.SDLK_D)) {
        action.* = .delete;
    } else if (event.type == c.SDL_EVENT_MOUSE_WHEEL and (c.SDL_GetModState() & c.SDL_KMOD_CTRL) != 0) {
        action.* = .{ .scale = .{ .wheel_y = event.wheel.y } };
    } else if (event.type == c.SDL_EVENT_MOUSE_WHEEL) {
        action.* = .{ .next_or_prev = .{ .wheel_y = event.wheel.y } };
    } else if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_SLASH) {
        action.* = .reset;
    }
}

inline fn check(ok: bool) void {
    if (!ok) h.printError();
}

// 是否是退出事件
fn isQuitEvent(event: c.SDL_Event) bool {
    if (event.type == c.SDL_EVENT_QUIT) { // 正常退出
        return true;
    }
    if (event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_ESCAPE) { // ESC 键
        return true;
    }
    return false;
}

// 是否是切换事件
fn isToggleEvent(event: c.SDL_Event, dst_rect: *c.SDL_FRect) bool {
    if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_RIGHT) { // 右键
        return true;
    } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_LEFT) { // 左键非图片区域
        return !isInRect(event, dst_rect);
    }
    return false;
}

// 是否是拖拽开始事件
fn isDragStartEvent(event: c.SDL_Event, dst_rect: *c.SDL_FRect) bool {
    const point = c.SDL_FPoint{ .x = event.button.x, .y = event.button.y };
    return event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and
        event.button.button == c.SDL_BUTTON_LEFT and
        c.SDL_PointInRectFloat(&point, dst_rect);
}

// 方向键的数组
const DIRECTION_KEYS = [_]c.SDL_Keycode{ c.SDLK_UP, c.SDLK_DOWN, c.SDLK_LEFT, c.SDLK_RIGHT };
// 是否是旋转
fn isRotateEvent(event: c.SDL_Event) bool {
    return event.type == c.SDL_EVENT_KEY_DOWN and
        std.mem.indexOfScalar(u32, &DIRECTION_KEYS, event.key.key) != null;
}

fn handleDragingEvent(event: c.SDL_Event, action: *EventAction) void {
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
fn mapKeyToAngle(key: c.SDL_Keycode) ?f64 {
    return switch (key) {
        c.SDLK_UP => 0.0,
        c.SDLK_DOWN => 180.0,
        c.SDLK_LEFT => 270.0,
        c.SDLK_RIGHT => 90.0,
        else => null,
    };
}

// 判断鼠标位置是否在图片上
fn isInRect(event: c.SDL_Event, dst_rect: *c.SDL_FRect) bool {
    const mouse_x = event.button.x;
    const mouse_y = event.button.y;
    return mouse_x >= dst_rect.x and mouse_x <= dst_rect.x + dst_rect.w and
        mouse_y >= dst_rect.y and mouse_y <= dst_rect.y + dst_rect.h;
}

// 重新计算 rect
fn calculateDstRect(dst_rect: *c.SDL_FRect, window: *Window, size: ISize(i32), offset: Point) void {
    const window_width = window.display_width;
    const window_height = window.display_height;

    dst_rect.w = @floatFromInt(size.w);
    dst_rect.h = @floatFromInt(size.h);
    const center_x: f32 = @floatFromInt(@divFloor(window_width - size.w, 2));
    const center_y: f32 = @floatFromInt(@divFloor(window_height - size.h, 2));

    dst_rect.x = center_x + offset.x;
    dst_rect.y = center_y + offset.y;
}

fn createTexture(renderer: *c.SDL_Renderer, image: *const LImage) Error!*c.SDL_Texture {
    // 计算 pitch
    const pitch = image.shape.w * image.shape.c;
    std.log.info("Pitch: {d}", .{pitch});
    // 创建图片纹理
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        image.shape.w,
        image.shape.h,
    );
    // 开启纹理混合模式
    if (!h.check(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND))) return Error.SdlSetTextureBlendModeFailed;
    // 上传纹理
    if (!h.check(c.SDL_UpdateTexture(
        texture,
        null,
        image.pixels_ptr,
        pitch,
    ))) return Error.SdlUpdateTextureFailed;

    return texture;
}
