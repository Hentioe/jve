const std = @import("std");
const Backend = @import("sdl/enums.zig").Backend;

pub const loader = @import("vips/loader.zig");
pub const writer = @import("vips/writer.zig");
pub const renderer = @import("sdl/renderer.zig");
pub const renderer_gpu = @import("sdl/renderer_gpu.zig");
pub const clipboard = @import("clipboard.zig");

pub fn load(file_path: []const u8) !loader.Image {
    return try loader.load(file_path);
}

pub fn render(allocator: std.mem.Allocator, backend: []const u8, image: loader.Image) !void {
    defer image.freePixels(); // 渲染结束后释放像素数据

    var current_renderer: ?Backend = null;
    if (std.mem.eql(u8, backend, "sdl_renderer")) {
        current_renderer = .SdlRenderer;
    } else if (std.mem.eql(u8, backend, "sdl_gpu")) {
        current_renderer = .SdlGpu;
    } else {
        std.log.err("Unknown backend: {s}", .{backend});
        return error.UnknownBackend;
    }

    // 在不同后端循环渲染（支持模式切换）
    while (current_renderer != null) {
        if (current_renderer == .SdlRenderer) {
            if (try renderer.render(allocator, image) == .Toggle) {
                current_renderer = .SdlGpu;
            } else {
                current_renderer = null;
            }
        } else if (current_renderer == .SdlGpu) {
            if (try renderer_gpu.render(allocator, image) == .Toggle) {
                current_renderer = .SdlRenderer;
            } else {
                current_renderer = null;
            }
        }
    }
}
