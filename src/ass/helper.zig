const std = @import("std");
const Error = @import("errors.zig").Error;

/// 根据传入值的类型，在编译期推导成功时的返回类型：
///   - 整数      -> `void`（0 表示成功）
///   - `?T`      -> `T`
///   - `[*c]T`   -> `[*c]T`（C 指针，非 `null` 才算成功）
fn Payload(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => void,
        .optional => |o| o.child,
        .pointer => |p| if (p.size == .c) T else @compileError("check: unsupported pointer type: " ++ @typeName(T)),
        else => @compileError("check: unsupported type: " ++ @typeName(T)),
    };
}

fn fail() Error {
    // libass 没有 SDL_GetError 这样的错误查询接口，
    // 详细信息只会通过 ass_set_message_cb 注册的回调输出。
    std.log.err("[LIBASS ERROR]: call failed (details are reported via the message callback)", .{});
    return Error.AssFailed;
}

/// 检查 libass 调用的返回值，失败则打印错误并返回 Error.AssFailed
///   - 整数      -> 非 0 表示失败
///   - `?T`      -> `null` 表示失败
///   - `[*c]T`   -> `null` 表示失败
pub fn check(value: anytype) Error!Payload(@TypeOf(value)) {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .int => {
            if (value != 0) return fail();
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

/// 用于返回「索引」的函数（如 `ass_alloc_style` / `ass_alloc_event`）：
/// 成功时返回 >= 0 的索引，失败时返回 -1。
/// 这里 0 是合法值，不能用 `check`。
pub fn checkIndex(value: c_int) Error!c_int {
    if (value < 0) return fail();
    return value;
}
