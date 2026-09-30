const std = @import("std");
const enums = @import("../enums.zig");
const Allocator = std.mem.Allocator;
const Image = @import("../../vips.zig").Image;
const Size = enums.Size;
const PixelLayout = enums.PixelLayout;
const Self = @This();

width: u32,
height: u32,
bands: u32,
data_ptr: *const anyopaque,

const Options = struct {
    new_size: ?Size = null,
    new_layout: ?PixelLayout = null,
    forced_bands: ?u32 = null,
    normalized: bool = false,
};

// 已预处理的
const Preprocessed = struct {
    width: u32,
    height: u32,
    bands: u32,
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
};

// todo: 添加错误集
// todo: 输出 vips 错误
pub fn preprocess(input: Self, allocator: Allocator, options: Options) !Preprocessed {
    var image = try Image.init(
        input.data_ptr,
        @intCast(input.width),
        @intCast(input.height),
        @intCast(input.bands),
        .UCHAR,
    );
    defer image.deinit();

    if (options.forced_bands == 3 and input.bands > 3) {
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
    if (options.new_layout) |layout| if (layout == .NCHW and options.normalized) {
        const src = @as([*]const f32, @ptrCast(@alignCast(out.data_ptr)))[0..out.data_size];
        const data = try buildNCHW(allocator, src, @intCast(image.width), @intCast(image.height), @intCast(image.bands));
        data_ptr = data.ptr;
    };

    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .bands = @intCast(image.bands),
        .format = image.format,
        .data_ptr = data_ptr,
        .data_size = out.data_size,
        .allocator = allocator,
        ._out = out,
    };
}

// todo: 添加错误处理集
pub fn buildNCHW(allocator: Allocator, src: []const f32, width: u32, height: u32, bands: u32) ![]f32 {
    const plane_size = width * height;
    const dst = try allocator.alloc(f32, plane_size * bands);
    for (0..height) |h| {
        for (0..width) |w| {
            const hwc_idx = (h * width + w) * bands;
            const hw_idx = h * width + w;
            for (0..bands) |c| {
                const idx = c * plane_size + hw_idx;
                dst[idx] = src[hwc_idx + c];
            }
        }
    }

    return dst;
}
