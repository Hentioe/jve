const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});
const LoadedImage = @import("image_loader.zig").Loaded;

pub const Error = error{
    SdlInitFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
};

// 注意：以下代码是 SDL3
pub fn render(loaded: LoadedImage) Error!void {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        printSdlError();
        return Error.SdlInitFailed;
    }
    // 创建窗口
    const window = c.SDL_CreateWindow(
        "Image Viewer",
        @intCast(loaded.width),
        @intCast(loaded.height),
        c.SDL_EVENT_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
    );
    if (window == null) {
        printSdlError();
        return Error.SdlInitFailed;
    }
    // 创建渲染器
    const renderer = c.SDL_CreateRenderer(window, null);
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
        printSdlError();
        return Error.SdlSetTextureBlendModeFailed;
    }
    // 上传纹理
    if (!c.SDL_UpdateTexture(
        texture,
        null,
        loaded.pixels_ptr,
        pitch,
    )) {
        printSdlError();
        return Error.SdlUpdateTextureFailed;
    }
    // 循环并处理 SDL 事件
    var running = true;
    var event: c.SDL_Event = undefined;
    while (running) {
        if (c.SDL_WaitEvent(&event)) {
            if (event.type == c.SDL_EVENT_QUIT) {
                running = false;
            }
        }
        _ = c.SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255); // 设置白色背景
        _ = c.SDL_RenderClear(renderer);
        _ = c.SDL_RenderTexture(renderer, texture, null, null);
        _ = c.SDL_RenderPresent(renderer);
    }
    c.SDL_DestroyTexture(texture);
    c.SDL_DestroyRenderer(renderer);
    c.SDL_DestroyWindow(window);
    c.SDL_Quit();
}

fn printSdlError() void {
    const err = c.SDL_GetError();
    std.debug.print("SDL Error: {s}\n", .{err});
    _ = c.SDL_ClearError();
}
