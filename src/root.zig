const std = @import("std");
const c = @cImport({
    @cInclude("vips/vips.h");
    @cInclude("SDL3/SDL.h");
});

const VipsLoadError = error{
    VipsInitFailed,
    VipsImageLoadFailed,
    OutOfMemory,
};

const SdlInitError = error{
    SdlInitFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
};

const Loaded = struct {
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    bands: u32,
    format: u32,
    size: usize,
    pixels_ptr: [*]c_ushort,

    pub fn deinit(self: Loaded) void {
        defer c.g_free(self.pixels_ptr);
    }

    // 访问特定像素
    pub fn pixel(self: Loaded, x: u32, y: u32) []c_ushort {
        const start = (y * self.width + x) * self.bands;
        const end = start + self.bands;
        return self.pixels_ptr[start..end];
    }
};

pub fn loadImage(allocator: std.mem.Allocator, path: []const u8) VipsLoadError!Loaded {
    if (c.vips_init("zig_image") != 0) {
        printVipsError();
        return VipsLoadError.VipsInitFailed;
    }
    const in = c.vips_image_new_from_file(@ptrCast(path));
    if (in == null) {
        printVipsError();
        return VipsLoadError.VipsImageLoadFailed;
    }
    defer c.g_object_unref(in);
    // 获取宽度
    const width = c.vips_image_get_width(in);
    // 获取高度
    const height = c.vips_image_get_height(in);
    // 获取通道数
    const bands = c.vips_image_get_bands(in);
    // 获取格式
    const format = c.vips_image_get_format(in);
    // 提取像素数据
    var size: usize = 0;
    const buffer_opaque = c.vips_image_write_to_memory(in, &size);
    const pixels_ptr: [*]c_ushort = @ptrCast(@alignCast(buffer_opaque));

    return Loaded{
        .allocator = allocator,
        .width = @intCast(width),
        .height = @intCast(height),
        .bands = @intCast(bands),
        .format = @intCast(format),
        .size = size,
        .pixels_ptr = pixels_ptr,
    };
}

// 注意：以下代码是 SDL3
pub fn initSdlWindow(loaded: Loaded) SdlInitError!void {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        printSdlError();
        return SdlInitError.SdlInitFailed;
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
        return SdlInitError.SdlInitFailed;
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
        return SdlInitError.SdlSetTextureBlendModeFailed;
    }
    // 上传纹理
    if (!c.SDL_UpdateTexture(
        texture,
        null,
        loaded.pixels_ptr,
        pitch,
    )) {
        printSdlError();
        return SdlInitError.SdlUpdateTextureFailed;
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

fn printVipsError() void {
    const err = c.vips_error_buffer();
    std.debug.print("VIPS Error: {s}\n", .{err});
    c.vips_error_clear();
}

fn printSdlError() void {
    const err = c.SDL_GetError();
    std.debug.print("SDL Error: {s}\n", .{err});
}
