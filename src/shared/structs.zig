const std = @import("std");
const SizeError = @import("errors.zig").SizeError;

/// 图片的尺寸结构体（Image Size）
pub fn ISize(comptime T: type) type {
    return struct {
        w: T,
        h: T,

        const Self = @This();

        /// 仅适用于 Size(u32)
        pub fn fromI32(w: i32, h: i32) SizeError!Self {
            if (T != u32) {
                @compileError("fromI32 is only available for Size(u32), got Size(" ++ @typeName(T) ++ ")");
            }
            if (w < 0 or h < 0) return SizeError.Negative;
            return .{ .w = @intCast(w), .h = @intCast(h) };
        }
    };
}

/// 图片的形状结构体（Image Shape）
pub fn IShape(comptime T: type) type {
    return struct {
        w: T,
        h: T,
        c: T,

        const Self = @This();

        pub fn to(self: Self, comptime U: type) IShape(U) {
            if ((T == i32 or T == u32) and (U == f32 or U == f64)) {
                return .{ .w = @floatFromInt(self.w), .h = @floatFromInt(self.h), .c = @floatFromInt(self.c) };
            }
            return .{ .w = @intCast(self.w), .h = @intCast(self.h), .c = @intCast(self.c) };
        }

        pub fn toISize(self: *const Self, comptime U: type) ISize(U) {
            if ((T == i32 or T == u32) and (U == f32 or U == f64)) {
                return .{ .w = @floatFromInt(self.w), .h = @floatFromInt(self.h) };
            }
            return .{ .w = @intCast(self.w), .h = @intCast(self.h) };
        }

        /// 计算数据大小
        pub fn calcSize(self: *const Self, byte_size: usize) usize {
            return @as(usize, @intCast(self.w * self.h * self.c)) * byte_size;
        }

        pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{d}x{d} ({d})", .{ self.w, self.h, self.c });
        }
    };
}

/// 表示二维点的结构体
pub fn Point(comptime T: type) type {
    return struct {
        x: T = std.mem.zeroes(T),
        y: T = std.mem.zeroes(T),
    };
}
