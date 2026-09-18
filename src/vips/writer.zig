const std = @import("std");
const c = @import("c.zig").c;
const initializer = @import("initializer.zig");
const consts = @import("consts.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;

pub fn saveRawPixels(
    pixels: *anyopaque,
    width: usize,
    height: usize,
    bands: usize,
    out_filename: []const u8,
) Error!void {
    // 初始化
    try initializer.initialize();
    // 假设像素数据为 8 位无符号整数 (0-255)
    const size: usize = width * height * bands;
    // 从内存指针创建 VipsImage
    const image = c.vips_image_new_from_memory(
        pixels,
        size,
        @intCast(width),
        @intCast(height),
        @intCast(bands),
        c.VIPS_FORMAT_UCHAR,
    );
    // 释放引用
    defer c.g_object_unref(image);
    // 写入文件（后缀如 .png, .jpg, .webp 决定输出格式）
    const status = c.vips_image_write_to_file(image, @ptrCast(out_filename), VIPS_ARGUMENT_NULL);

    if (status != 0) {
        return Error.VipsSaveFailed;
    }
}
