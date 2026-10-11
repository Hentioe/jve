/// 栅格化后的文字位图。
///
/// 只暴露文字渲染管线所需的纯数据（覆盖率位图 + 尺寸 + 颜色），不再携带
/// `ass.Image`，因此文字管线无需了解 libass。
const std = @import("std");
const ass = @import("ass");
const Self = @This();

allocator: std.mem.Allocator,
track: *ass.Track,
width: u32,
height: u32,
pixels: []u8, // 单通道覆盖率，长度 = width * height
color: u32, // 来自 ASS_Image.color（RGBA 字节序）
detect_change: c_int,

pub fn deinit(self: *Self) void {
    self.allocator.free(self.pixels);
    ass.c.ass_free_track(self.track);
    self.* = undefined;
}
