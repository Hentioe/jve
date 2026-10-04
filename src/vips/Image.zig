const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const Error = @import("errors.zig").Error;
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const IShape = @import("../structs.zig").IShape;
const Self = @This();

pub const Format = enum(c_int) {
    UCHAR = c.VIPS_FORMAT_UCHAR,
    FLOAT = c.VIPS_FORMAT_FLOAT,
};

// Out 结构体便于回收内存（避免外部调用 glib）
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

width: i32,
height: i32,
channels: i32,
format: Format,
_in: *c.VipsImage,

pub fn init(input_ptr: *const anyopaque, shape: IShape(i32), format: Format) Error!Self {
    const byte_size: usize = if (format == .FLOAT) @sizeOf(f32) else @sizeOf(u8);
    const in = c.vips_image_new_from_memory_copy(
        input_ptr,
        shape.calcSize(byte_size),
        shape.w,
        shape.h,
        shape.c,
        @intFromEnum(format),
    ) orelse return Error.VipsImageNewFromMemoryFailed;

    return Self{
        .width = shape.w,
        .height = shape.h,
        .channels = shape.c,
        .format = format,
        ._in = in,
    };
}

// 从文件加载图像，返回 Image 实例
pub fn initFromFile(allocator: std.mem.Allocator, path: []const u8) Error!Self {
    const extension = std.fs.path.extension(path);
    const filename = try allocator.dupeZ(u8, path);
    defer allocator.free(filename);

    // 从文件创建 VipsImage 指针
    var in: [*c]c.VipsImage = null;
    if (std.mem.eql(u8, extension, ".avif")) {
        std.log.info("Heif loading...", .{});
        if (!h.check(c.vips_heifload(filename, &in, "n", @as(c_int, 1), VIPS_ARGUMENT_NULL))) { // 对 avif 特殊处理（仅获取第一帧）
            return Error.VipsHeifLoadFailed;
        }
    } else {
        in = c.vips_image_new_from_file(filename, VIPS_ARGUMENT_NULL);
    }
    if (in == null) {
        h.printError();
        return Error.VipsImageLoadFailed;
    }

    // 获取通道数
    const channels = c.vips_image_get_bands(in);
    if (channels < 3) {
        c.g_object_unref(in);
        return Error.UnsupportedChannels;
    }

    var self = Self{
        .width = c.vips_image_get_width(in),
        .height = c.vips_image_get_height(in),
        .channels = channels,
        .format = .UCHAR, // 占位，toSrgb 会更新为真实格式
        ._in = in,
    };
    errdefer self.deinit();

    // 强制转换为 sRGB：高色深图像（如 USHORT）会在此被转换为 UCHAR
    try self.toSrgb();

    return self;
}

// 将图像转换为 sRGB 色彩空间
pub fn toSrgb(self: *Self) Error!void {
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_colourspace(self._in, &out, c.VIPS_INTERPRETATION_sRGB, VIPS_ARGUMENT_NULL))) {
        return Error.VipsImageLoadFailed;
    }
    c.g_object_unref(self._in); // 释放原始图像
    self._in = out.?; // 更新为 sRGB 图像
    self.width = c.vips_image_get_width(self._in);
    self.height = c.vips_image_get_height(self._in);
    self.channels = c.vips_image_get_bands(self._in);
    self.format = try formatFromVips(c.vips_image_get_format(self._in)); // sRGB 后格式通常为 UCHAR
}

fn formatFromVips(value: c_int) Error!Format {
    return switch (value) {
        c.VIPS_FORMAT_UCHAR => .UCHAR,
        c.VIPS_FORMAT_FLOAT => .FLOAT,
        else => Error.UnsupportedFormat,
    };
}

pub fn deinit(self: *Self) void {
    c.g_object_unref(self._in);
    self.* = undefined;
}

pub fn removeAlpha(self: *Self) Error!void {
    if (self.channels != 4) return;
    var out: ?*c.VipsImage = null;
    const white: f64 = if (self.format == .FLOAT) 1.0 else 255.0;
    const bg = c.vips_array_double_newv(3, white, white, white, VIPS_ARGUMENT_NULL);
    defer c.vips_area_unref(c.VIPS_AREA(bg));
    if (!h.check(c.vips_flatten(self._in, &out, "background", bg, VIPS_ARGUMENT_NULL))) {
        return Error.VipsFlattenFailed;
    }
    c.g_object_unref(self._in); // 释放原始图像
    self._in = out.?; // 更新为去掉 Alpha 通道后的图像
    self.channels = c.vips_image_get_bands(self._in);
}

pub fn addAlpha(self: *Self, alpha: f64) Error!void {
    if (self.channels == 4) return;
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_bandjoin_const1(self._in, &out, alpha, VIPS_ARGUMENT_NULL))) {
        return Error.VipsBandJoinConst2Failed;
    }
    c.g_object_unref(self._in);
    self._in = out.?; // 更新为添加 Alpha 通道后的图像
    self.channels = c.vips_image_get_bands(self._in);
}

// 将单通道灰度图复制为 RGB 三通道（用于把模型输出的单通道 mask 交给需要 RGBA 的渲染器）
pub fn toRgb(self: *Self) Error!void {
    if (self.channels >= 3) return;
    var images = [_]?*c.VipsImage{ self._in, self._in, self._in };
    var out: ?*c.VipsImage = null;
    if (!h.check(c.vips_bandjoin(@ptrCast(&images), &out, 3, VIPS_ARGUMENT_NULL))) {
        return Error.VipsBandJoinFailed;
    }
    c.g_object_unref(self._in);
    self._in = out.?; // 更新为复制成 RGB 后的图像
    self.channels = c.vips_image_get_bands(self._in);
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

// 将图像写入一块新内存并返回 Out 结构体
pub fn allocOutInMemory(self: *Self) Error!Out {
    var size: usize = 0;
    const data_ptr = c.vips_image_write_to_memory(self._in, &size) orelse return Error.VipsWriteToMemoryFailed;
    // 检查 size 是否和计算的一致
    const byte_size: usize = if (self.format == .FLOAT) @sizeOf(f32) else @sizeOf(u8);
    std.debug.assert(size == @as(usize, @intCast(self.width * self.height * self.channels)) * byte_size);
    return Out.init(data_ptr, size);
}
