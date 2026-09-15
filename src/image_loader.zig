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
    width: usize,
    height: usize,
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
    var bands = c.vips_image_get_bands(in);
    // 获取格式
    const format = c.vips_image_get_format(in);
    // 转换为 SRGB
    var srgb: [*c]c.VipsImage = null;
    if (c.vips_colourspace(in, &srgb, c.VIPS_INTERPRETATION_sRGB) != 0) {
        printVipsError();
        return Error.VipsImageLoadFailed;
    }
    defer c.g_object_unref(srgb);
    // 转换为 RGBA
    var rgba: [*c]c.VipsImage = null;
    if (c.vips_image_hasalpha(srgb) != 0) {
        rgba = srgb;
    } else {
        if (c.vips_addalpha(srgb, &rgba) != 0) {
            printVipsError();
            return Error.VipsImageLoadFailed;
        }
        bands += 1;
    }
    defer c.g_object_unref(rgba);
    // 提取像素数据
    var size: usize = 0;
    const pixels_ptr: [*]c_ushort = @ptrCast(@alignCast(
        c.vips_image_write_to_memory(rgba, &size),
    ));

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
