const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Error = @import("errors.zig").Error;
const Self = @This();

pub const Format = enum(c_int) {
    UCHAR = c.VIPS_FORMAT_UCHAR,
    FLOAT = c.VIPS_FORMAT_FLOAT,
};

pub const Out = struct {
    data_ptr: *anyopaque,
    data_size: usize,

    pub fn init(data_ptr: *anyopaque, size: usize) Out {
        return Out{ .data_ptr = data_ptr, .data_size = size };
    }

    pub fn deinit(self: *Out) void {
        c.g_free(self.data_ptr);
        self.* = undefined;
    }
};

_in: *c.VipsImage,
width: i32,
height: i32,
bands: i32,
format: Format,

pub fn init(input_ptr: *const anyopaque, width: i32, height: i32, bands: i32, format: Format) Error!Self {
    const format_bytes: usize = if (format == .FLOAT) @sizeOf(f32) else @sizeOf(u8);
    const u_width: usize = @intCast(width);
    const u_height: usize = @intCast(height);
    const u_bands: usize = @intCast(bands);
    const in = c.vips_image_new_from_memory_copy(
        input_ptr,
        u_width * u_height * u_bands * format_bytes,
        width,
        height,
        bands,
        @intFromEnum(format),
    ) orelse return Error.VipsImageNewFromMemoryFailed;

    return Self{
        .width = width,
        .height = height,
        .bands = bands,
        .format = format,
        ._in = in,
    };
}

pub fn deinit(self: *Self) void {
    c.g_object_unref(self._in);
    self.* = undefined;
}

pub fn removeAlpha(self: *Self) Error!void {
    if (self.bands != 4) return;
    var out: ?*c.VipsImage = null;
    const white: f64 = if (self.format == .FLOAT) 1.0 else 255.0;
    const bg = c.vips_array_double_newv(3, white, white, white, VIPS_ARGUMENT_NULL);
    defer c.vips_area_unref(c.VIPS_AREA(bg));
    if (!h.check(c.vips_flatten(self._in, &out, "background", bg, VIPS_ARGUMENT_NULL))) {
        return Error.VipsFlattenFailed;
    }
    c.g_object_unref(self._in); // 释放原始图像
    self._in = out.?; // 更新为去掉 Alpha 通道后的图像
    self.bands = c.vips_image_get_bands(self._in);
}

pub fn addAlpha(self: *Self, alpha: f64) Error!void {
    if (self.bands == 4) return;
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_bandjoin_const1(self._in, &out, alpha, VIPS_ARGUMENT_NULL))) {
        return Error.VipsBandJoinConst2Failed;
    }
    c.g_object_unref(self._in);
    self._in = out.?; // 更新为添加 Alpha 通道后的图像
    self.bands = c.vips_image_get_bands(self._in);
}

// 将单通道灰度图复制为 RGB 三通道（用于把模型输出的单通道 mask 交给需要 RGBA 的渲染器）
pub fn toRgb(self: *Self) Error!void {
    if (self.bands >= 3) return;
    var images = [_]?*c.VipsImage{ self._in, self._in, self._in };
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_bandjoin(@ptrCast(&images), &out, 3, VIPS_ARGUMENT_NULL))) {
        return Error.VipsBandJoinFailed;
    }
    c.g_object_unref(self._in);
    self._in = out.?; // 更新为复制成 RGB 后的图像
    self.bands = c.vips_image_get_bands(self._in);
}

pub fn resize(self: *Self, new_width: i32, new_height: i32) Error!void {
    // 计算缩放参数
    const scale_x = @as(f64, @floatFromInt(new_width)) / @as(f64, @floatFromInt(self.width));
    const scale_y = @as(f64, @floatFromInt(new_height)) / @as(f64, @floatFromInt(self.height));

    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_resize(self._in, &out, scale_x, "vscale", scale_y, VIPS_ARGUMENT_NULL))) {
        return Error.VipsResizeFailed;
    }
    c.g_object_unref(self._in); // 释放原始图像
    self._in = out.?;
    self.width = c.vips_image_get_width(self._in);
    self.height = c.vips_image_get_height(self._in);
}

// 归一化
pub fn normalize(self: *Self) Error!void {
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_linear1(self._in, &out, 1.0 / 255.0, 0.0, VIPS_ARGUMENT_NULL))) {
        return Error.VipsLinear1Failed;
    }
    c.g_object_unref(self._in); // 释放原始图像
    self._in = out.?; // 更新为归一化后的图像
    self.format = .FLOAT; // 更新为浮点格式
}

pub fn allocOutInMemory(self: *Self) Error!Out {
    var size: usize = 0;
    const data_ptr = c.vips_image_write_to_memory(self._in, &size) orelse return Error.VipsWriteToMemoryFailed;
    // 检查 size 是否和计算的一致
    const bytes: usize = if (self.format == .FLOAT) @sizeOf(f32) else @sizeOf(u8);
    std.debug.assert(size == @as(usize, @intCast(self.width * self.height * self.bands)) * bytes);
    return Out.init(data_ptr, size);
}
