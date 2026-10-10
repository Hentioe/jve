const c = @import("sdl").c;
const h = @import("sdl").h;
const std = @import("std");
const Allocator = std.mem.Allocator;
const Format = @import("enums.zig").ScreenshotFormat;

pub const Error = @import("sdl").Error || std.mem.Allocator.Error;

var lock: std.Thread.Mutex = .{};
var global_data: ?[]const u8 = null;
var global_allocator: ?Allocator = null;

pub fn copyImage(allocator: Allocator, src: []const u8, format: Format) Error!void {
    var mime_types = [_][*c]const u8{switch (format) {
        .png => "image/png",
    }};
    lock.lock();
    defer lock.unlock();

    try h.check(c.SDL_SetClipboardData(
        callback,
        cleanup,
        null,
        &mime_types,
        mime_types.len,
    ));

    const dst = try allocator.alloc(u8, src.len);
    @memcpy(dst, src);

    global_data = dst;
    global_allocator = allocator;
}

// 提供数据的回调函数
fn callback(_: ?*anyopaque, _: [*c]const u8, size: [*c]usize) callconv(.c) ?*const anyopaque {
    lock.lock();
    defer lock.unlock();
    if (global_data) |data| {
        std.log.info("Providing clipboard data, size: {d}", .{data.len});
        size.* = data.len;
        return data.ptr;
    }
    std.log.warn("No clipboard data available", .{});

    size.* = 0;
    return null;
}

// 清理数据的回调函数
fn cleanup(_: ?*anyopaque) callconv(.c) void {
    std.log.info("Cleaning up clipboard data", .{});
    std.debug.assert(global_allocator != null);
    if (global_data) |data| global_allocator.?.free(data);
    global_data = null;
}
