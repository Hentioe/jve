const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const initializer = @import("initializer.zig");
const format = @import("format.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;

pub const Image = struct {
    file_name: []const u8,
    width: i32,
    height: i32,
    bands: i32,
    format: i32,
    size: usize,
    pixels_ptr: [*]c_ushort,

    pub fn freePixels(self: *Image) void {
        c.g_free(self.pixels_ptr);
        self.pixels_ptr = undefined;
    }

    pub fn deinit(self: *Image) void {
        self.freePixels();
        self.* = undefined;
    }
};

pub fn load(path: []const u8) Error!Image {
    // 获取扩展名
    const extension = std.fs.path.extension(path);
    if (!try format.isSupported(extension)) { // 主动检查格式是否支持
        return Error.UnsupportedFormat;
    }
    // 从文件创建 VipsImage
    const in = c.vips_image_new_from_file(@ptrCast(path), VIPS_ARGUMENT_NULL);
    defer c.g_object_unref(in);
    if (in == null) {
        h.printError();
        return Error.VipsImageLoadFailed;
    }
    // 从 path 中提取文件名
    const file_name = std.fs.path.basename(path);
    // 获取宽度
    const width = c.vips_image_get_width(in);
    // 获取高度
    const height = c.vips_image_get_height(in);
    // 获取通道数
    var bands = c.vips_image_get_bands(in);
    // 获取格式
    const _format = c.vips_image_get_format(in);
    // 转换为 SRGB
    var srgb: [*c]c.VipsImage = null;
    if (c.vips_colourspace(in, &srgb, c.VIPS_INTERPRETATION_sRGB, VIPS_ARGUMENT_NULL) != 0) {
        h.printError();
        return Error.VipsImageLoadFailed;
    }
    defer c.g_object_unref(srgb);
    // 转换为 RGBA
    var rgba: [*c]c.VipsImage = null;
    if (c.vips_image_hasalpha(srgb) != 0) {
        rgba = srgb;
    } else {
        if (c.vips_addalpha(srgb, &rgba, VIPS_ARGUMENT_NULL) != 0) {
            h.printError();
            return Error.VipsImageLoadFailed;
        }
        bands += 1;
    }
    defer {
        if (rgba != srgb) c.g_object_unref(rgba); // 只有在 rgba 与 srgb 不同的情况下才释放 rgba
    }
    // 提取像素数据
    var size: usize = 0;
    const pixels_ptr: [*]c_ushort = @ptrCast(@alignCast(
        c.vips_image_write_to_memory(rgba, &size),
    ));

    return Image{
        .file_name = file_name,
        .width = width,
        .height = height,
        .bands = bands,
        .format = _format,
        .size = size,
        .pixels_ptr = pixels_ptr,
    };
}
