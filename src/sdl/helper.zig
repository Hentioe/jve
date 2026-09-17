const std = @import("std");
const c = @import("c.zig").c;

pub fn printSdlError() void {
    const err = c.SDL_GetError();
    std.log.err("SDL Error: {s}", .{err});
    _ = c.SDL_ClearError();
}
