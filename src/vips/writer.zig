const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const root = @import("../root.zig");
const consts = @import("consts.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;
const IShape = root.IShape;

/// 保存像素到图像文件，预设为 8 位无符号整数 (0-255) 的像素数据
pub fn savePixelsToFile(pixels_ptr: *anyopaque, shape: IShape(i32), out_filename: []const u8) Error!void {
    const size = shape.calcSize(1);
    // 从像素数据指针创建 VipsImage
    const in = c.vips_image_new_from_memory(
        pixels_ptr,
        size,
        shape.w,
        shape.h,
        shape.c,
        c.VIPS_FORMAT_UCHAR,
    );
    if (in == null) return Error.VipsImageNewFromMemoryFailed;
    defer c.g_object_unref(in); // 释放图像引用
    // 写入文件（后缀决定输出格式）
    if (c.vips_image_write_to_file(in, @ptrCast(out_filename), VIPS_ARGUMENT_NULL) != 0) {
        h.printError();
        return Error.VipsWriteToFileFailed;
    }
}

pub const Encoder = struct {
    const Self = @This();

    pixels_ptr: *anyopaque,
    shape: IShape(i32),
    encoded: ?[]u8 = null,

    pub fn init(pixels_ptr: *anyopaque, shape: IShape(i32)) Self {
        return Self{
            .pixels_ptr = pixels_ptr,
            .shape = shape,
        };
    }

    pub fn encode(self: *Self) Error!void {
        // 假设像素数据为 8 位无符号整数 (0-255)
        const size: usize = self.shape.calcSize(1);
        // 从像素数据指针创建 VipsImage
        const in = c.vips_image_new_from_memory(
            self.pixels_ptr,
            size,
            self.shape.w,
            self.shape.h,
            self.shape.c,
            c.VIPS_FORMAT_UCHAR,
        );
        defer c.g_object_unref(in); // 释放图像引用
        // 编码为 PNG 数据到内存缓冲区
        var buf: ?*anyopaque = null;
        var len: usize = 0;
        if (c.vips_pngsave_buffer(in, &buf, &len, VIPS_ARGUMENT_NULL) != 0) {
            h.printError();
            return Error.VipsEncodingFailed;
        }
        const u8_ptr: [*]u8 = @ptrCast(buf);
        self.encoded = u8_ptr[0..len];
    }

    pub fn deinit(self: *Self) void {
        if (self.encoded) |data| c.g_free(data.ptr);
        self.* = undefined;
    }
};
