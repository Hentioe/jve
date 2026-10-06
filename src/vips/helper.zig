const std = @import("std");
const c = @import("c.zig").c;

pub fn printError() void {
    const err_buf = c.vips_error_buffer();
    const err_msg = std.mem.trim( // 去掉首尾空白字符
        u8,
        err_buf[0 .. std.mem.len(err_buf) - 1],
        &std.ascii.whitespace,
    );
    std.log.err("[VIPS ERROR]: {s}", .{err_msg});
    c.vips_error_clear();
}

pub fn check(status: c_int) bool {
    const ok = status == 0;
    if (!ok) printError();

    return ok;
}
