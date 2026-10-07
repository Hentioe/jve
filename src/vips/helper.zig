const std = @import("std");
const c = @import("c.zig").c;
const VipsError = @import("errors.zig").VipsError;

/// 根据传入值的类型，在编译期推导成功时的返回类型：
///   - `c_int`  -> `void`
///   - `?T`     -> `T`
///   - `[*c]T`  -> `[*c]T`
fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => if (T == c_int) void else @compileError("check: only c_int is supported, received: " ++ @typeName(T)),
        .optional => |o| o.child,
        .pointer => |p| if (p.size == .c) T else @compileError("check: unsupported pointer type " ++ @typeName(T)),
        else => @compileError("check: unsupported type: " ++ @typeName(T)),
    };
}

fn fail() VipsError {
    const msg = std.mem.trim(u8, std.mem.span(c.vips_error_buffer()), &std.ascii.whitespace);
    std.log.err("[VIPS ERROR]: {s}", .{msg});
    c.vips_error_clear();
    return VipsError.VipsFailed;
}

/// 检查 VIPS 调用的返回值，如果失败则打印错误并返回 VipsError.VipsFailed
/// 当传入值是以下类型时：
///   - `c_int`  -> 非 `0` 表示失败
///   - `?T`     -> `null` 表示失败
///   - `[*c]T`  -> `null` 表示失败
pub fn check(value: anytype) VipsError!Payload(@TypeOf(value)) {
    switch (@typeInfo(@TypeOf(value))) {
        .int => if (value != 0) return fail(),
        .optional => return value orelse fail(),
        .pointer => {
            if (value == null) return fail();
            return value;
        },
        else => unreachable, // 已被 Payload 在编译期拦截
    }
}
