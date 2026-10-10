const std = @import("std");
const SizeError = @import("errors.zig").SizeError;

/// 表示二维尺寸的结构体（Width x Height）
pub fn Size2D(comptime T: type) type {
    return struct {
        w: T,
        h: T,

        const Self = @This();

        pub fn to(self: Self, comptime U: type) Size2D(U) {
            return castFields(Size2D(U), self);
        }

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
            return castFields(IShape(U), self);
        }

        pub fn toSize2D(self: *const Self, comptime U: type) Size2D(U) {
            return castFields(Size2D(U), self);
        }

        /// 计算数据大小
        pub fn calcSize(self: *const Self, comptime U: type) usize {
            return @as(usize, @intCast(self.w * self.h * self.c)) * @sizeOf(U);
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

/// 标量转换：int/float 之间任意互转
pub fn castScalar(comptime U: type, x: anytype) U {
    const T = @TypeOf(x);
    if (T == U) return x;

    return switch (@typeInfo(T)) {
        .int, .comptime_int => switch (@typeInfo(U)) {
            .int => @intCast(x),
            .float => @floatFromInt(x),
            else => @compileError("unsupported: " ++ @typeName(T) ++ " -> " ++ @typeName(U)),
        },
        .float, .comptime_float => switch (@typeInfo(U)) {
            .int => @intFromFloat(x),
            .float => @floatCast(x),
            else => @compileError("unsupported: " ++ @typeName(T) ++ " -> " ++ @typeName(U)),
        },
        else => @compileError("unsupported: " ++ @typeName(T) ++ " -> " ++ @typeName(U)),
    };
}

/// 结构体转换：按字段名逐个转换，目标结构体 Dst 决定每个字段的目标类型
pub fn castFields(comptime Dst: type, src: anytype) Dst {
    var out: Dst = undefined;
    inline for (@typeInfo(Dst).@"struct".fields) |f| {
        @field(out, f.name) = castScalar(f.type, @field(src, f.name));
    }
    return out;
}
