const std = @import("std");
const ass = @import("ass");
const Error = ass.Error;

// 显示层唯一的 `ass.Library`，所有 `ass.Renderer` 绑定到同一 `ass.Library` 上。
// 初次访问自动初始化，由 `display` 负责销毁。
var instance: ass.Library = undefined;
var initialized: bool = false;

/// 返回 `ass.Library` 的只读指针，未初始化时会自动初始化。
pub fn get() Error!*const ass.Library {
    if (!initialized) {
        instance = try ass.Library.init();
        ass.c.ass_set_message_cb(instance.ass_library, assLog, null);
        initialized = true;
    }
    return &instance;
}

fn humanLevel(level: c_int) []const u8 {
    return switch (level) {
        0 => "none",
        1 => "fatal",
        2 => "error",
        3 => "warning",
        4 => "info",
        5 => "debug",
        6 => "trace",
        else => "unknown",
    };
}

fn assLog(level: c_int, fmt: [*c]const u8, args: [*c]ass.c.struct___va_list_tag_1, data: ?*anyopaque) callconv(.c) void {
    _ = data;
    if (level > 5) return; // 6 是 libass 的 trace 级别，太吵可以过滤
    var buf: [1024]u8 = undefined;
    const n = ass.c.vsnprintf(&buf, buf.len, fmt, args);
    if (n > 0) std.debug.print("{s}: {s}\n", .{ humanLevel(level), std.mem.sliceTo(&buf, 0) });
}

/// 由 `display.deinit` 在 `SDL_Quit` 之前调用。
pub fn deinit() void {
    if (initialized) {
        instance.deinit();
        instance = undefined;
        initialized = false;
    }
}
