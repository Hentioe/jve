const c = @import("vips_c");
const h = @import("helper.zig");
const shared = @import("shared");
const consts = @import("consts.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;
const IShape = shared.IShape;

/// 保存像素到图像文件，预设为 8 位无符号整数 (0-255) 的像素数据
pub fn saveToFile(data_ptr: *anyopaque, shape: IShape(i32), filename: [:0]const u8) Error!void {
    const size = shape.calcSize(u8);
    // 从像素数据指针创建 VipsImage
    const in = try h.check(c.vips_image_new_from_memory(
        data_ptr,
        size,
        shape.w,
        shape.h,
        shape.c,
        c.VIPS_FORMAT_UCHAR,
    ));
    defer c.g_object_unref(in); // 释放图像引用
    // 写入文件（后缀决定输出格式）
    try h.check(c.vips_image_write_to_file(in, filename, VIPS_ARGUMENT_NULL));
}

pub const Encoder = struct {
    const Self = @This();

    const Format = enum { png };
    const Encoded = struct {
        data: []u8,

        pub fn deinit(self: *Self) void {
            c.g_free(self.data.ptr);
            self.* = undefined;
        }
    };

    format: Format,

    pub fn init(format: Format) Self {
        return Self{ .format = format };
    }

    pub fn encode(_: *Self, data_ptr: *const anyopaque, shape: IShape(i32)) Error!Encoded {
        // 假设像素数据为 8 位无符号整数 (0-255)
        const size: usize = shape.calcSize(u8);
        // 从像素数据指针创建 VipsImage
        const in = try h.check(c.vips_image_new_from_memory(
            data_ptr,
            size,
            shape.w,
            shape.h,
            shape.c,
            c.VIPS_FORMAT_UCHAR,
        ));
        defer c.g_object_unref(in); // 释放图像引用
        var buf: ?*anyopaque = null;
        var len: usize = 0;
        // 当前默认编码为 PNG
        try h.check(c.vips_pngsave_buffer(in, &buf, &len, VIPS_ARGUMENT_NULL));
        const data = @as([*]u8, @ptrCast(buf))[0..len];
        return Encoded{ .data = data };
    }
};
