const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const Extractor = @import("Extractor.zig");
const Self = @This();

pub const Error = sdl.Error || std.mem.Allocator.Error;

// 应用唯一的全局数据缓存，由 root 在初始化/反初始化时管理生命周期。
// 不持有显示相关的资源（Viewer、GPU 设备、窗口等），因此释放顺序无强依赖。
var instance: Self = undefined;

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
preview_initialized: bool = false,
extracted: ?Extractor = null,

pub fn init(allocator: Allocator) void {
    instance = Self{ .allocator = allocator };
}

pub fn deinit() void {
    if (instance.extracted) |*extractor| extractor.deinit();
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

pub fn writeTexture(self: *Self, device: *const sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, device, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}
