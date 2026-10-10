const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const extractor = @import("extractor.zig");
const Self = @This();

pub const Error = sdl.Error || std.mem.Allocator.Error || sdl.Error;

// 应用唯一的全局数据缓存，由 root 在初始化/反初始化时管理生命周期。
// 不持有显示相关的资源（Viewer、GPU 设备、窗口等），因此释放顺序无强依赖。
var instance: Self = undefined;

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
preview_initialized: bool = false,
extracted: ?extractor.Extracted = null,

pub fn init(allocator: Allocator) void {
    instance = Self{ .allocator = allocator };
}

pub fn deinit() void {
    if (instance.extracted) |*extracted| extracted.deinit();
    instance = undefined;
}

// 只读访问
pub fn reader() *const Self {
    return &instance;
}

// 可变访问
pub fn writer() *Self {
    return &instance;
}

/// 提取并缓存纹理像素
pub fn writeTexture(self: *Self, allocator: Allocator, device: *const sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    self.extracted = try extractor.extract(
        allocator,
        device,
        gpu_texture,
        self.image_shape.to(u32),
    );
}

/// 读取像素缓存，创建纹理（模式切换返回预览时复用）
pub fn readTexture(self: *Self, renderer: *sdl.Renderer) Error!?*sdl.Texture {
    if (self.extracted) |*extracted| {
        defer {
            extracted.deinit(); // 读取后释放已提取数据
            self.extracted = null; // 避免 deinit 重复释放
        }
        const data_prt = extracted.data.ptr;
        const shape = self.image_shape;
        const pitch = shape.w * shape.c; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建纹理
        const texture = try renderer.createTexture(
            sdl.c.SDL_PIXELFORMAT_RGBA32,
            sdl.c.SDL_TEXTUREACCESS_STATIC,
            shape.w,
            shape.h,
        );
        // 开启纹理混合模式
        try sdl.Renderer.setTextureBlendMode(texture, sdl.c.SDL_BLENDMODE_BLEND);
        // 上传纹理
        try sdl.Renderer.updateTexture(texture, null, data_prt, pitch);

        return texture;
    }

    return null;
}
