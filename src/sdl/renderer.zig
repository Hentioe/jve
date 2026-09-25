const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const structs = @import("structs.zig");
const root = @import("../root.zig");
const album = root.album;
const State = @import("State.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Image = @import("../root.zig").loader.Image;
const Point = structs.Point;
const RenderNext = @import("enums.zig").RenderNext;

// 基于 sdl_renderer 渲染图片
pub fn render(_: std.mem.Allocator, state: *State) Error!RenderNext {
    var image = album.current() catch return Error.AlbumError;
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
    calculateDstRect(&dst_rect, window, image.width, image.height, .{});

    // 循环并处理 SDL 事件
    var running = true;
    var toggle = false;
    var animating = true;
    var event: c.SDL_Event = undefined;
    // 其它控制参数
    var target_angle = state.target_angle; // 目标旋转角度
    var is_dragging: bool = false; // 是否正在拖动
    var movement_offset = state.movement_offset; // 移动偏移量
    // 累计缩放倍率
    var target_scale: f32 = state.target_scale;
    var current_scale: f32 = 1.0;
    while (running) {
        const has_event = if (animating) c.SDL_PollEvent(&event) else c.SDL_WaitEvent(&event);
        if (has_event) {
            if (isQuitEvent(event)) {
                running = false;
            } else if (isToggleEvent(event, &dst_rect)) {
                running = false;
                toggle = true;
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_LEFT) {
                const mouse_pt = c.SDL_FPoint{ .x = event.button.x, .y = event.button.y };
                if (c.SDL_PointInRectFloat(&mouse_pt, &dst_rect)) { // 检查点击位置是否在纹理矩形范围内
                    is_dragging = true;
                    std.log.info("Started dragging at mouse position: ({}, {})", .{ mouse_pt.x, mouse_pt.y });
                }
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_UP and event.button.button == c.SDL_BUTTON_LEFT) {
                // 停止拖动
                is_dragging = false;
                animating = false;
            } else if (event.type == c.SDL_EVENT_MOUSE_MOTION and is_dragging) {
                // 更新移动偏移量
                movement_offset.x += event.motion.xrel;
                movement_offset.y += event.motion.yrel;
                animating = true;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    c.SDLK_UP => target_angle = 0.0,
                    c.SDLK_DOWN => target_angle = 180.0,
                    c.SDLK_LEFT => target_angle = 270.0,
                    c.SDLK_RIGHT => target_angle = 90.0,
                    c.SDLK_SLASH => { // 重置所有控制参数
                        target_angle = 0.0;
                        target_scale = 1.0;
                        current_scale = 1.0;
                        is_dragging = false;
                        movement_offset = .{};
                        animating = true;
                    },
                    else => {},
                }
            } else if (event.type == c.SDL_EVENT_MOUSE_WHEEL) {
                const mod_state = c.SDL_GetModState();
                if (mod_state > 0) {
                    // 计算新的缩放率、宽度，并更新窗口大小
                    if (event.wheel.y > 0) target_scale *= 1.4 else target_scale /= 1.4;
                    if (target_scale > 3) target_scale = 3.0 else if (target_scale < 0.5) target_scale = 0.5;
                    animating = true;
                } else {
                    std.log.debug("Mouse wheel event without modifier: {d}", .{event.wheel.y});
                    // 切换图片
                    if (event.wheel.y < 0) {
                        _ = album.next() catch |err| {
                            std.log.err("Failed to switch to next image: {}", .{err});
                        };
                    } else {
                        _ = album.prev() catch |err| {
                            std.log.err("Failed to switch to previous image: {}", .{err});
                        };
                    }
                    const crrent = album.current() catch |err| blk: {
                        std.log.err("Failed to get current image: {}", .{err});
                        break :blk null;
                    };
                    if (crrent) |refreshed_image| {
                        image = refreshed_image;
                        c.SDL_DestroyTexture(texture);
                        texture = try createTexture(renderer, &refreshed_image);
                    }
                    animating = true; // 动画触发 dst_rect 更新
                }
            }
        }
        if (animating) {
            current_scale += (target_scale - current_scale) * 0.002;
            if (c.SDL_fabsf(target_scale - current_scale) < 0.0001) {
                current_scale = target_scale;
            }
            if (current_scale == target_scale) {
                animating = false;
            }
            std.log.debug("current_scale: {any}, target_scale: {any}, diff: {d}", .{ current_scale, target_scale, target_scale - current_scale });
            const new_width: i32 = @intFromFloat(@as(f32, @floatFromInt(image.width)) * current_scale);
            const new_height: i32 = @intFromFloat(@as(f32, @floatFromInt(image.height)) * current_scale);
            calculateDstRect(&dst_rect, window, new_width, new_height, movement_offset);
            window.imageSizeUpdated(new_width, new_height);
        }
        const alpha: u8 = if (window.has_border) 255 else 60; // 根据边框模式设置背景透明度
        check(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, alpha)); // 设置白色背景
        check(c.SDL_RenderClear(renderer));
        check(c.SDL_RenderTextureRotated(renderer, texture, null, &dst_rect, target_angle, null, c.SDL_FLIP_NONE));
        check(c.SDL_RenderPresent(renderer));
    }
    // 更新状态中控制参数
    state.target_angle = target_angle;
    state.target_scale = target_scale;
    state.movement_offset = movement_offset;
    // 通知状态停止渲染
    state.stopRendering();

    return if (toggle) .toggle else .quit;
}

inline fn check(ok: bool) void {
    if (!ok) {
        h.printError();
    }
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

// 判断鼠标位置是否在图片上
fn isInRect(event: c.SDL_Event, dst_rect: *c.SDL_FRect) bool {
    const mouse_x = event.button.x;
    const mouse_y = event.button.y;
    return mouse_x >= dst_rect.x and mouse_x <= dst_rect.x + dst_rect.w and
        mouse_y >= dst_rect.y and mouse_y <= dst_rect.y + dst_rect.h;
}

// 待删除：此后端不再需要窗口模式
// fn toggleWindowModel(window: *Window, dst_rect: *c.SDL_FRect, animating: *bool) void {
//     // 切换边框模式
//     window.toggleBorder();
//     // 重建 dst_rect
//     updateImageRect(dst_rect, window, window.image_width, window.image_height);
//     if (window.has_border) {
//         animating.* = false;
//     }
// }

// 重新计算 rect
fn calculateDstRect(dst_rect: *c.SDL_FRect, window: *Window, new_width: i32, new_height: i32, offset: Point) void {
    const window_width = window.display_width;
    const window_height = window.display_height;
    // 待删除：此后端不再需要窗口模式
    // if (window.has_border) {
    //     window_width = window.image_width;
    //     window_height = window.image_height;
    // }
    dst_rect.w = @floatFromInt(new_width);
    dst_rect.h = @floatFromInt(new_height);
    const center_x: f32 = @floatFromInt(@divFloor(window_width - new_width, 2));
    const center_y: f32 = @floatFromInt(@divFloor(window_height - new_height, 2));

    dst_rect.x = center_x + offset.x;
    dst_rect.y = center_y + offset.y;
}

fn createTexture(renderer: *c.SDL_Renderer, image: *const Image) Error!*c.SDL_Texture {
    // 计算 pitch
    const pitch = image.width * image.bands;
    std.log.info("Pitch: {d}", .{pitch});
    // 创建图片纹理
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        image.width,
        image.height,
    );
    // 开启纹理混合模式
    if (!h.check(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND))) {
        return Error.SdlSetTextureBlendModeFailed;
    }
    // 上传纹理
    if (!c.SDL_UpdateTexture(
        texture,
        null,
        image.pixels_ptr,
        pitch,
    )) {
        h.printError();
        return Error.SdlUpdateTextureFailed;
    }

    return texture;
}
