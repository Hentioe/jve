const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const format = @import("format.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;

pub const Image = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8, // 涉及内存申请
    file_name: []const u8, // file_path 的切片
    width: i32,
    height: i32,
    bands: i32,
    format: i32,
    size: usize,
    pixels_ptr: [*c]c_ushort, // vips 的指针

    pub fn deinit(self: *Image) void {
        self.allocator.free(self.file_path);
        c.g_free(self.pixels_ptr);
        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) Error!Image {
    // 获取扩展名
    const extension = std.fs.path.extension(path);
    if (!try format.isSupported(extension)) return Error.UnsupportedFormat; // 主动检查格式是否支持

    const filename = try allocator.dupeZ(u8, path);
    defer allocator.free(filename);

    // 从文件创建 VipsImage 指针
    var in: [*c]c.VipsImage = null;
    if (std.mem.eql(u8, extension, ".avif") and !h.check(
        c.vips_heifload(filename, &in, "n", @as(c_int, 1), VIPS_ARGUMENT_NULL), // 对 avif 特殊处理（仅获取第一帧）
    )) {
        return Error.VipsHeifLoadFailed;
    } else {
        in = c.vips_image_new_from_file(filename, VIPS_ARGUMENT_NULL);
    }
    if (in == null) {
        h.printError();
        return Error.VipsImageLoadFailed;
    }
    defer c.g_object_unref(in);

    // 获取通道数
    var bands = c.vips_image_get_bands(in);
    if (bands < 3) return Error.UnsupportedBands;
    // 获取宽度
    const width = c.vips_image_get_width(in);
    // 获取高度
    const height = c.vips_image_get_height(in);
    // 获取格式
    const _format = c.vips_image_get_format(in);

    // 转换为 SRGB
    var srgb: [*c]c.VipsImage = null;
    if (!h.check(c.vips_colourspace(in, &srgb, c.VIPS_INTERPRETATION_sRGB, VIPS_ARGUMENT_NULL))) return Error.VipsImageLoadFailed;
    defer c.g_object_unref(srgb);

    // 转换为 RGBA
    var rgba: [*c]c.VipsImage = null;
    if (c.vips_image_hasalpha(srgb) != 0) { // 如果有 alpha 通道，不转换
        rgba = srgb;
    } else {
        if (!h.check(c.vips_addalpha(srgb, &rgba, VIPS_ARGUMENT_NULL))) return Error.VipsAddAlphaFailed;
        bands += 1;
    }
    defer {
        if (rgba != srgb) c.g_object_unref(rgba); // 只有在 rgba 与 srgb 不同的情况下才释放 rgba
    }
    // 提取像素数据
    var size: usize = 0;
    const pixels_ptr: [*c]c_ushort = @ptrCast(@alignCast(
        c.vips_image_write_to_memory(rgba, &size),
    ));

    // 将外部传入的 path 复制一遍
    const file_path = try allocator.alloc(u8, path.len);
    @memcpy(file_path, path);

    return Image{
        .allocator = allocator,
        .file_path = file_path,
        .file_name = std.fs.path.basename(file_path),
        .width = width,
        .height = height,
        .bands = bands,
        .format = _format,
        .size = size,
        .pixels_ptr = pixels_ptr,
    };
}
