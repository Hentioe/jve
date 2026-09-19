const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const initializer = @import("initializer.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Image = @import("../root.zig").loader.Image;
const RenderExit = @import("enums.zig").RenderExit;

// 注意：以下代码是 SDL3
pub fn render(allocator: std.mem.Allocator, image: Image) Error!RenderExit {
    // 执行初始化
    try initializer.initialize(.SdlRenderer);
    // 创建窗口
    var window = try Window.create(
        allocator,
        image.width,
        image.height,
        .{ .has_border = false, .backend = .SdlRenderer },
    );
    defer window.destroy();
    // 更新窗口标题
    try window.setTitle(image.file_name);
    // 创建渲染器
    const renderer = c.SDL_CreateRenderer(window.sdl_window, null) orelse {
        h.printError();
        return Error.SdlCreateRendererFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);
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
    defer c.SDL_DestroyTexture(texture);
    // 开启纹理混合模式
    if (!c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND)) {
        h.printError();
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
    // 创建目标矩形
    var dst_rect = c.SDL_FRect{};
    updateImageRect(&dst_rect, window, image.width, image.height);

    // 循环并处理 SDL 事件
    var running = true;
    var toggle = false;
    var animating = false;
    var event: c.SDL_Event = undefined;
    // 其它控制参数
    var angle: f32 = 0.0; // 旋转角度
    // 累计缩放倍率
    var target_scale: f32 = 1.0;
    var current_scale: f32 = 1.0;
    while (running) {
        const has_event = if (animating) c.SDL_PollEvent(&event) else c.SDL_WaitEvent(&event);
        if (has_event) {
            if (isQuitEvent(event)) {
                running = false;
            } else if (isToggleEvent(event, &dst_rect)) {
                running = false;
                toggle = true;
            } else if (event.type == c.SDL_EVENT_KEY_DOWN) {
                switch (event.key.key) {
                    c.SDLK_W, c.SDLK_UP => angle = 0.0,
                    c.SDLK_S, c.SDLK_DOWN => angle = 180.0,
                    c.SDLK_A, c.SDLK_LEFT => angle = 270.0,
                    c.SDLK_D, c.SDLK_RIGHT => angle = 90.0,
                    c.SDLK_SLASH => { // 重置所有控制参数
                        angle = 0.0;
                        target_scale = 1.0;
                        current_scale = 1.0;
                        animating = true;
                    },
                    else => {},
                }
            } else if (event.type == c.SDL_EVENT_MOUSE_WHEEL) {
                // 计算新的缩放率、宽度，并更新窗口大小
                if (event.wheel.y > 0) target_scale *= 1.4 else target_scale /= 1.4;
                if (target_scale > 3) target_scale = 3.0 else if (target_scale < 1) target_scale = 1.0;
                animating = true;
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
            updateImageRect(
                &dst_rect,
                window,
                new_width,
                new_height,
            );
            window.imageSizeUpdated(new_width, new_height);
        }
        const alpha: u8 = if (window.has_border) 255 else 60; // 根据边框模式设置背景透明度
        check(c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, alpha)); // 设置白色背景
        check(c.SDL_RenderClear(renderer));
        check(c.SDL_RenderTextureRotated(renderer, texture, null, &dst_rect, angle, null, c.SDL_FLIP_NONE));
        check(c.SDL_RenderPresent(renderer));
    }

    return if (toggle) .Toggle else .Quit;
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

fn updateImageRect(dst_rect: *c.SDL_FRect, window: *Window, new_width: i32, new_height: i32) void {
    const window_width = window.display_width;
    const window_height = window.display_height;
    // 待删除：此后端不再需要窗口模式
    // if (window.has_border) {
    //     window_width = window.image_width;
    //     window_height = window.image_height;
    // }
    dst_rect.w = @floatFromInt(new_width);
    dst_rect.h = @floatFromInt(new_height);
    dst_rect.x = @floatFromInt(@divFloor(window_width - new_width, 2));
    dst_rect.y = @floatFromInt(@divFloor(window_height - new_height, 2));
}
