const std = @import("std");
const Self = @This();

err: anyerror,
src: std.builtin.SourceLocation,
msg_buf: [1024]u8 = undefined,
msg_len: usize = 0,

pub fn message(self: *const Self) []const u8 {
    return self.msg_buf[0..self.msg_len];
}
