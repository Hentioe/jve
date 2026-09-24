const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const ort = @import("ort");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Image = @import("../root.zig").loader.Image;
const Size = @import("structs.zig").Size(i32);
const Extractor = @import("Extractor.zig");
const Self = @This();

allocator: Allocator,
size: Size,
bands: i32,
target_scale: f32 = 1.0,
extractor: ?Extractor = null,
ort_api: ?ort.Api = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{
        .allocator = allocator,
        .size = .{ .w = 0, .h = 0 },
        .bands = 0,
    };
}

pub fn deinit(self: *Self) void {
    if (self.extractor) |*extractor| extractor.deinit();
    if (self.ort_api) |*ort_api| ort_api.deinit();
    self.* = undefined;
}

pub fn updateFromImage(self: *Self, image: *const Image) void {
    self.size = .{ .w = image.width, .h = image.height };
    self.bands = image.bands;
}

pub fn writeTexture(self: *Self, device: *c.SDL_GPUDevice, gpu_texture: ?*c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extractor = Extractor.init(self.allocator, device, self.size.w, self.size.h, self.bands);
    // 下载纹理
    try extractor.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extractor = extractor;
}

pub fn readTexture(self: *Self, renderer: *c.SDL_Renderer) Error!?*c.SDL_Texture {
    if (self.extractor) |*extractor| {
        defer extractor.deinit(); // 读取后释放下载数据
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
        const pixels_ptr = try extractor.getAndCheckDataPtr();
        if (!c.SDL_UpdateTexture(
            texture,
            null,
            pixels_ptr,
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
