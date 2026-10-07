const std = @import("std");
const c = @import("c.zig").c;
const Error = @import("errors.zig").Error;

/// 根据传入值的类型，在编译期推导成功时的返回类型：
///   - `bool`   -> `void`
///   - `?T`     -> `T`
///   - `[*c]T`  -> `[*c]T`（C 指针，非 `null` 才算成功）
fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .bool => void,
        .optional => |o| o.child,
        .pointer => |p| if (p.size == .c) T else @compileError("check: unsupported pointer type: " ++ @typeName(T)),
        else => @compileError("check: unsupported type: " ++ @typeName(T)),
    };
}

fn fail() Error {
    const err = c.SDL_GetError();
    std.log.err("[SDL ERROR]: {s}", .{err});
    if (c.SDL_ClearError()) std.log.debug("[SDL ERROR CLEARED]", .{});
    return Error.SdlFailed;
}

/// 检查 SDL 调用的返回值，如果失败则打印错误并返回 SdlError.SdlFailed
/// 当传入值是以下类型时：
///   - `bool`   -> `false` 表示失败
///   - `?T`     -> `null` 表示失败
///   - `[*c]T`  -> `null` 表示失败
pub fn check(value: anytype) Error!Payload(@TypeOf(value)) {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool => {
            if (!value) return fail();
        },
        .optional => {
            return value orelse fail();
        },
        .pointer => {
            if (value == null) return fail();
            return value;
        },
        else => unreachable, // 已被 Payload 在编译期拦截
    }
}
