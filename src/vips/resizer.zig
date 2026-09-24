const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const Error = @import("errors.zig").Error;
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;

pub const Result = struct {
    width: u32,
    height: u32,
    bands: u32,
    data_size: usize,
    data_ptr: *anyopaque,

    pub fn deinit(self: *Result) void {
        c.g_free(self.data_ptr);
        self.* = undefined;
    }
};

pub const ResizeOptions = struct {
    input_normalize: bool = false,
    output_normalize: bool = false,
    force_input_bands: ?i32 = null,
    force_output_bands: ?i32 = null,
};

pub fn resize(
    input_ptr: ?*const anyopaque,
    width: i32,
    height: i32,
    bands: i32,
    new_width: i32,
    new_height: i32,
    options: ResizeOptions,
) Error!Result {
    const format = if (options.input_normalize) c.VIPS_FORMAT_FLOAT else c.VIPS_FORMAT_UCHAR;
    const in_byte_size: i32 = if (options.input_normalize) @sizeOf(f32) else @sizeOf(u8);
    var in = c.vips_image_new_from_memory(
        input_ptr,
        @intCast(width * height * bands * in_byte_size),
        width,
        height,
        bands,
        format,
    );
    var new_input_bands = bands;
    if (options.force_input_bands == 3 and bands != 3) {
        var tmp: ?*c.VipsImage = null;
        const pixel = @as(f32, 255.0);
        const bg = c.vips_array_double_newv(3, pixel, pixel, pixel, VIPS_ARGUMENT_NULL);
        if (!h.check(c.vips_flatten(in, &tmp, "background", bg, VIPS_ARGUMENT_NULL))) {
            c.vips_area_unref(c.VIPS_AREA(bg));
            return Error.VipsFlattenFailed;
        }
        c.vips_area_unref(c.VIPS_AREA(bg));
        c.g_object_unref(in); // 释放原始图像
        in = tmp;
        new_input_bands = options.force_input_bands.?; // 更新通道数量
    }
    defer c.g_object_unref(in);

    // 缩放
    const scale_x = @as(f64, @floatFromInt(new_width)) / @as(f64, @floatFromInt(width));
    const scale_y = @as(f64, @floatFromInt(new_height)) / @as(f64, @floatFromInt(height));
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_resize(in, &out, scale_x, "vscale", scale_y, VIPS_ARGUMENT_NULL))) {
        return Error.VipsResizeFailed;
    }
    defer c.g_object_unref(out);
    // 归一化
    if (options.output_normalize) {
        var tmp: ?*c.VipsImage = null;
        if (!h.check(c.vips_linear1(out, &tmp, 1.0 / 255.0, 0.0, VIPS_ARGUMENT_NULL))) {
            return Error.VipsLinear1Failed;
        }
        c.g_object_unref(out);
        out = tmp;
    }

    var output_bands = new_input_bands;
    if (options.force_output_bands == 4 and new_input_bands != options.force_output_bands) {
        const alpha_val: f64 = 255.0;
        var tmp: ?*c.VipsImage = null;
        if (!h.check(c.vips_bandjoin_const1(out, &tmp, alpha_val, VIPS_ARGUMENT_NULL))) {
            return Error.VipsBandJoinConst2Failed;
        }
        c.g_object_unref(out);
        out = tmp;
        output_bands = options.force_output_bands.?; // 更新输出通道数量
    }

    var data_size: usize = 0;
    const data_ptr = c.vips_image_write_to_memory(out, &data_size);
    const out_byte_size: i32 = if (options.input_normalize or options.output_normalize) @sizeOf(f32) else @sizeOf(u8);

    std.debug.assert(data_size == new_width * new_height * output_bands * out_byte_size); // 输出的大小和计算出来的应该相同，以确保正确性

    return Result{
        .width = @intCast(new_width),
        .height = @intCast(new_height),
        .bands = @intCast(output_bands),
        .data_size = data_size,
        .data_ptr = data_ptr.?,
    };
}
