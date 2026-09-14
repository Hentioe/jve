const std = @import("std");
const c = @import("c.zig").c;

pub fn printSdlError() void {
    const err = c.SDL_GetError();
    std.debug.print("SDL Error: {s}\n", .{err});
    _ = c.SDL_ClearError();
}
