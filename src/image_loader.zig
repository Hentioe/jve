const std = @import("std");
const c = @cImport({
    @cInclude("vips/vips.h");
});

pub const Error = error{
    VipsInitFailed,
    VipsImageLoadFailed,
    OutOfMemory,
};

pub const Loaded = struct {
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

pub fn loadImage(allocator: std.mem.Allocator, path: []const u8) Error!Loaded {
    if (c.vips_init("zig_image") != 0) {
        printVipsError();
        return Error.VipsInitFailed;
    }
    const in = c.vips_image_new_from_file(@ptrCast(path));
    if (in == null) {
        printVipsError();
        return Error.VipsImageLoadFailed;
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

fn printVipsError() void {
    const err = c.vips_error_buffer();
    std.debug.print("VIPS Error: {s}\n", .{err});
    c.vips_error_clear();
}
