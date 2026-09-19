const std = @import("std");

pub const loader = @import("vips/loader.zig");
pub const writer = @import("vips/writer.zig");
pub const renderer = @import("sdl/renderer.zig");
pub const renderer_gpu = @import("sdl/renderer_gpu.zig");

pub fn load(file_path: []const u8) !loader.Image {
    return try loader.load(file_path);
}

pub fn render(allocator: std.mem.Allocator, backend: []const u8, image: loader.Image) !void {
    if (std.mem.eql(u8, backend, "sdl_renderer")) {
        _ = try renderer.render(allocator, image);
    } else if (std.mem.eql(u8, backend, "sdl_gpu")) {
        try renderer_gpu.render(allocator, image);
    } else {
        std.log.err("Unknown backend: {s}", .{backend});
        return error.UnknownBackend;
    }
}
