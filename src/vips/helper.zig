const std = @import("std");
const c = @import("c.zig").c;

pub fn printError() void {
    const err = c.vips_error_buffer();
    std.log.err("[VIPS ERROR]: {s}", .{err});
    c.vips_error_clear();
}

pub fn check(status: c_int) bool {
    const ok = status == 0;
    if (!ok) printError();

    return ok;
}
