const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Downloader = @import("Downloader.zig");

const Cache = struct {
    width: i32 = 0,
    height: i32 = 0,
    bands: i32 = 0,
    downloader: ?Downloader = null,
    pixels_ptr: ?*anyopaque = null,

    pub fn writeTexture(
        self: *Cache,
        allocator: std.mem.Allocator,
        device: *c.SDL_GPUDevice,
        gpu_texture: ?*c.SDL_GPUTexture,
        width: i32,
        height: i32,
        bands: i32,
    ) Error!void {
        self.width = width;
        self.height = height;
        self.bands = bands;
        // 创建下载器
        var downloader = Downloader.init(allocator, device, width, height, bands);
        // 下载纹理
        try downloader.downloadGpuTexture(gpu_texture);
        // 像素数据指针
        self.pixels_ptr = try downloader.pixelsPtr();
        self.downloader = downloader;
    }

    pub fn readAndUpdateTexture(self: *Cache, renderer: *c.SDL_Renderer) Error!?*c.SDL_Texture {
        if (self.pixels_ptr == null) {
            return null;
        }
        defer {
            if (self.downloader) |*downloader| {
                // 释放已下载的纹理像素
                downloader.deinit();
                self.downloader = null;
                self.pixels_ptr = null;
            }
        }
        // 计算 pitch
        const pitch = self.width * self.bands;
        std.log.info("Pitch: {d}", .{pitch});
        // 创建图片纹理
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            self.width,
            self.height,
        );
        // 开启纹理混合模式
        if (!c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND)) {
            h.printError();
            return Error.SdlSetTextureBlendModeFailed;
        }
        // 上传纹理
        if (!c.SDL_UpdateTexture(
            texture,
            null,
            self.pixels_ptr,
            pitch,
        )) {
            h.printError();
            return Error.SdlUpdateTextureFailed;
        }

        return texture;
    }
};

var cache: Cache = .{};

pub fn writer() *Cache {
    return &cache;
}

pub fn reader() *Cache {
    return &cache;
}
