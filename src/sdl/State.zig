const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Allocator = std.mem.Allocator;
const Image = @import("../root.zig").loader.Image;
const Size = @import("structs.zig").Size(i32);
const Downloader = @import("Downloader.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
size: Size,
bands: i32,
downloaded: ?Downloader = null,
target_scale: f32 = 1.0,

pub fn init(allocator: Allocator) Self {
    return Self{ .allocator = allocator, .size = .{ .w = 0, .h = 0 }, .bands = 0 };
}

pub fn deinit(self: *Self) void {
    if (self.downloaded) |*downloaded| {
        downloaded.deinit();
        self.* = undefined;
    }
}

pub fn updateFromImage(self: *Self, image: *const Image) void {
    self.size = .{ .w = image.width, .h = image.height };
    self.bands = image.bands;
}

pub fn writeTexture(self: *Self, device: *c.SDL_GPUDevice, gpu_texture: ?*c.SDL_GPUTexture) Error!void {
    // 创建下载器
    var downloader = Downloader.init(self.allocator, device, self.size.w, self.size.h, self.bands);
    // 下载纹理
    try downloader.downloadGpuTexture(gpu_texture);
    // 缓存已下载的内容
    self.downloaded = downloader;
}

pub fn readTexture(self: *Self, renderer: *c.SDL_Renderer) Error!?*c.SDL_Texture {
    if (self.downloaded) |*downloaded| {
        defer downloaded.deinit(); // 读取后释放下载数据
        const pitch = self.size.w * self.bands; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建图片纹理
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            self.size.w,
            self.size.h,
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
            try downloaded.pixelsPtr(),
            pitch,
        )) {
            h.printError();
            return Error.SdlUpdateTextureFailed;
        }

        return texture;
    } else {
        return null;
    }
}
