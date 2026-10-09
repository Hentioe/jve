const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const Preview = @import("Preview.zig");
const Gpu = @import("Gpu.zig");
const Extractor = @import("Extractor.zig");
const Self = @This();

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
preview: ?Preview = null,
gpu: ?Gpu = null,
extracted: ?Extractor = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    if (self.preview) |*preview| preview.deinit();
    if (self.gpu) |*gpu| gpu.deinit();
    if (self.extracted) |*extractor| extractor.deinit();
    self.* = undefined;
}

pub fn writeTexture(self: *Self, device: *sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, device, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}
