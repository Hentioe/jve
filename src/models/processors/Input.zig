const std = @import("std");
const enums = @import("../enums.zig");
const root = @import("../../root.zig");
const Allocator = std.mem.Allocator;
const IShape = root.IShape;
const ISize = root.ISize;
const PixelLayout = enums.PixelLayout;
const Position = @import("../Position.zig");
const Image = @import("../../vips.zig").Image;
const Self = @This();

shape: IShape(u32),
data_ptr: *const anyopaque,
click_position: ?Position = null,

const Options = struct {
    new_size: ?ISize(i32) = null,
    new_layout: ?PixelLayout = null,
    forced_channels: ?u32 = null,
    normalized: bool = false,
};

// 已预处理的
const Preprocessed = struct {
    shape: IShape(u32),
    format: Image.Format,
    data_ptr: *anyopaque,
    data_size: usize,
    allocator: Allocator,
    _out: Image.Out,

    pub fn deinit(self: *Preprocessed) void {
        if (self.data_ptr != self._out.data_ptr) {
            const slice = @as([*]u8, @ptrCast(@alignCast(self.data_ptr)))[0..self.data_size];
            if (self.format == .FLOAT) {
                self.allocator.rawFree(slice, .of(f32), @returnAddress());
            } else {
                self.allocator.rawFree(slice, .of(u8), @returnAddress());
            }
        }
        self._out.deinit();
    }

    pub fn Data(self: *Preprocessed, T: type) []T {
        return @as([*]T, @ptrCast(@alignCast(self.data_ptr)))[0 .. self.data_size / @sizeOf(T)];
    }
};

// todo: 添加错误集
// todo: 输出 vips 错误
pub fn preprocess(input: Self, allocator: Allocator, options: Options) !Preprocessed {
    var image = try Image.init(input.data_ptr, input.shape.to(i32), .UCHAR);
    defer image.deinit();

    if (options.forced_channels == 3 and input.shape.c > 3) {
        try image.removeAlpha();
    }

    if (options.new_size) |size| {
        try image.resize(size.w, size.h);
    }

    if (options.normalized) {
        try image.normalize();
    }

    const out = try image.allocOutInMemory();
    var data_ptr = out.data_ptr;
    const shape: IShape(u32) = .{ .w = @intCast(image.width), .h = @intCast(image.height), .c = @intCast(image.channels) };
    if (options.new_layout) |layout| if (layout == .NCHW and options.normalized) {
        const src = @as([*]const f32, @ptrCast(@alignCast(out.data_ptr)))[0..out.data_size];
        const data = try buildNCHW(allocator, src, shape);
        data_ptr = data.ptr;
    };

    return .{
        .shape = shape,
        .format = image.format,
        .data_ptr = data_ptr,
        .data_size = out.data_size,
        .allocator = allocator,
        ._out = out,
    };
}

// todo: 添加错误集
pub fn buildNCHW(allocator: Allocator, src: []const f32, shape: IShape(u32)) ![]f32 {
    const width = shape.w;
    const height = shape.h;
    const channels = shape.c;
    const plane_size = width * height;
    const dst = try allocator.alloc(f32, plane_size * channels);
    for (0..height) |h| {
        for (0..width) |w| {
            const hwc_idx = (h * width + w) * channels;
            const hw_idx = h * width + w;
            for (0..channels) |c| {
                const idx = c * plane_size + hw_idx;
                dst[idx] = src[hwc_idx + c];
            }
        }
    }

    return dst;
}
