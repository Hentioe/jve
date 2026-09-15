const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const LoadedImage = @import("../loader.zig").Loaded;

// 注意：以下代码是 SDL3
pub fn render(allocator: std.mem.Allocator, loaded: LoadedImage) Error!void {
    // 初始化窗口
    var window = try Window.init(
        allocator,
        loaded.width,
        loaded.height,
        false,
    );
    defer window.deinit();
    // 更新窗口标题
    window.setTitle(loaded.file_name);
    // 创建渲染器
    const renderer = c.SDL_CreateRenderer(window.sdl_window, null);
    const pitch: c_int = @intCast(loaded.width * loaded.bands);
    // 打印 pitch
    std.debug.print("Pitch: {d}\n", .{pitch});
    // 创建纹理
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        @intCast(loaded.width),
        @intCast(loaded.height),
    );
    // 开启纹理混合模式
    if (!c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND)) {
        helper.printSdlError();
        return Error.SdlSetTextureBlendModeFailed;
    }
    // 上传纹理
    if (!c.SDL_UpdateTexture(
        texture,
        null,
        loaded.pixels_ptr,
        pitch,
    )) {
        helper.printSdlError();
        return Error.SdlUpdateTextureFailed;
    }
    // 创建目标矩形
    var dst_rect = c.SDL_FRect{};
    updateImageRect(&dst_rect, window, loaded.width, loaded.height);

    std.debug.print("Destination Rect: x={d}, y={d}, w={d}, h={d}\n", .{ dst_rect.x, dst_rect.y, dst_rect.w, dst_rect.h });
    // 生成棋盘格（显示透明背景）
    const tile_size = 12;
    const parten_size = tile_size * 2;
    const checker_pixels = try allocator.alloc(u8, @intCast(parten_size * parten_size * 4));
    var y: usize = 0;
    while (y < parten_size) : (y += 1) {
        var x: usize = 0;
        while (x < parten_size) : (x += 1) {
            const offset = (y * parten_size + x) * 4;
            const is_white = ((x / tile_size) % 2) == ((y / tile_size) % 2);
            const color: u8 = if (is_white) 144 else 100;
            checker_pixels[offset + 0] = color;
            checker_pixels[offset + 1] = color;
            checker_pixels[offset + 2] = color;
            checker_pixels[offset + 3] = 255;
        }
    }
    // 上传棋盘格纹理
    const checker_texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        parten_size,
        parten_size,
    );
    if (!c.SDL_UpdateTexture(
        checker_texture,
        null,
        checker_pixels.ptr,
        parten_size * 4,
    )) {
        helper.printSdlError();
        return Error.SdlUpdateTextureFailed;
    }
    // 回收图像内存
    loaded.deinit();
    allocator.free(checker_pixels);
    // 循环并处理 SDL 事件
    var running = true;
    var animating = false;
    var event: c.SDL_Event = undefined;
    // 累计缩放倍率
    var target_scale: f32 = 1.0;
    var current_scale: f32 = 1.0;
    while (running) {
        const has_event = if (animating) c.SDL_PollEvent(&event) else c.SDL_WaitEvent(&event);
        if (has_event) {
            if (isQuitEvent(event, window.has_border)) {
                running = false;
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_RIGHT) {
                window.toggleBorder(); // 切换边框模式
                // 重建 dst_rect
                updateImageRect(&dst_rect, window, window.image_width, window.image_height);
                if (window.has_border) {
                    animating = false;
                }
            } else if (event.type == c.SDL_EVENT_MOUSE_WHEEL and !window.has_border) {
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
            std.debug.print("current_scale: {any}, target_scale: {any}, diff: {d}\n", .{ current_scale, target_scale, target_scale - current_scale });
            const new_width: usize = @intFromFloat(@as(f32, @floatFromInt(loaded.width)) * current_scale);
            const new_height: usize = @intFromFloat(@as(f32, @floatFromInt(loaded.height)) * current_scale);
            updateImageRect(
                &dst_rect,
                window,
                new_width,
                new_height,
            );
            window.imageSizeUpdated(new_width, new_height);
        }
        const alpha: u8 = if (window.has_border) 255 else 60; // 根据边框模式设置背景透明度
        _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, alpha); // 设置白色背景
        _ = c.SDL_RenderClear(renderer);
        if (window.has_border) {
            _ = c.SDL_RenderTextureTiled(renderer, checker_texture, null, 1.0, null);
        }
        _ = c.SDL_RenderTexture(renderer, texture, null, @ptrCast(&dst_rect));
        _ = c.SDL_RenderPresent(renderer);
    }
    c.SDL_DestroyTexture(texture);
    c.SDL_DestroyTexture(checker_texture);
    c.SDL_DestroyRenderer(renderer);
}

// 是否是退出事件
fn isQuitEvent(event: c.SDL_Event, has_border: bool) bool {
    if (event.type == c.SDL_EVENT_QUIT) {
        return true;
    }
    if (!has_border and event.type == c.SDL_EVENT_KEY_DOWN and event.key.key == c.SDLK_ESCAPE) {
        return true;
    }
    return false;
}

fn updateImageRect(dst_rect: *c.SDL_FRect, window: *Window, new_width: usize, new_height: usize) void {
    const window_width, const window_height = window.currentSize();
    dst_rect.w = @floatFromInt(new_width);
    dst_rect.h = @floatFromInt(new_height);
    dst_rect.x = @floatFromInt((window_width - new_width) / 2);
    dst_rect.y = @floatFromInt((window_height - new_height) / 2);
}
