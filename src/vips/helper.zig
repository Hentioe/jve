const std = @import("std");
const c = @import("c.zig").c;

pub fn printError() void {
    const err = c.vips_error_buffer();
    std.log.err("VIPS Error: {s}", .{err});
    c.vips_error_clear();
}
