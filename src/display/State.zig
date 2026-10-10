const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const Viewer = @import("Viewer.zig");
const Extractor = @import("Extractor.zig");
const Self = @This();

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
preview_viewer: ?Viewer = null,
gpu_viewer: ?Viewer = null,
extracted: ?Extractor = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    if (self.preview_viewer) |preview| preview.destroy();
    if (self.gpu_viewer) |gpu| gpu.destroy();
    if (self.extracted) |*extractor| extractor.deinit();
    self.* = undefined;
}

// 指定模式的 Viewer 实例是否已创建。
pub fn has(self: *Self, mode: Viewer.Mode) bool {
    return switch (mode) {
        .preview => self.preview_viewer != null,
        .gpu => self.gpu_viewer != null,
    };
}

// 惰性初始化并返回指定模式的 Viewer 实例，跨模式切换时复用。
pub fn viewer(self: *Self, mode: Viewer.Mode) Error!*Viewer {
    const slot = switch (mode) {
        .preview => &self.preview_viewer,
        .gpu => &self.gpu_viewer,
    };
    if (slot.* == null) slot.* = try Viewer.create(self.allocator, mode, self);
    return &slot.*.?;
}

pub fn writeTexture(self: *Self, device: *sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, device, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}
