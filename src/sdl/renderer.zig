const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const LoadedImage = @import("../image_loader.zig").Loaded;

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
    var event: c.SDL_Event = undefined;
    while (running) {
        if (c.SDL_WaitEvent(&event)) {
            if (isQuitEvent(event, window.has_border)) {
                running = false;
            } else if (event.type == c.SDL_EVENT_MOUSE_BUTTON_DOWN and event.button.button == c.SDL_BUTTON_RIGHT) {
                window.toggleBorder(); // 切换边框模式
            }
        }
        const alpha: u8 = if (window.has_border) 255 else 0; // 根据边框模式设置背景透明度
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, alpha); // 设置白色背景
        _ = c.SDL_RenderClear(renderer);
        if (window.has_border) {
            _ = c.SDL_RenderTextureTiled(renderer, checker_texture, null, 1.0, null);
        }
        _ = c.SDL_RenderTexture(renderer, texture, null, null);
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
