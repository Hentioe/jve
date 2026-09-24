const std = @import("std");
const vips_initializer = @import("vips/initializer.zig");
const vips_format = @import("vips/format.zig");
const VipsError = @import("vips/errors.zig").Error;
const Backend = @import("sdl/enums.zig").Backend;

pub const album = @import("album.zig");
pub const loader = @import("vips/loader.zig");
pub const writer = @import("vips/writer.zig");
pub const renderer = @import("sdl/renderer.zig");
pub const renderer_gpu = @import("sdl/renderer_gpu.zig");
pub const State = @import("sdl/State.zig");
pub const clipboard = @import("clipboard.zig");

pub fn initialize(allocator: std.mem.Allocator, file_path: []const u8) !void {
    try vips_initializer.initialize(allocator);
    try album.initialize(allocator, file_path);
}

pub fn shutdown() void {
    vips_initializer.shutdown();
    album.shutdown();
}

pub fn isSupported(suffix: []const u8) VipsError!bool {
    return try vips_format.isSupported(suffix);
}

pub fn extensions() VipsError![]const []const u8 {
    return try vips_format.extensions();
}

pub fn load(file_path: []const u8) !loader.Image {
    return try loader.load(file_path);
}

pub fn render(allocator: std.mem.Allocator, backend: []const u8) !void {
    var current_renderer: ?Backend = null;
    if (std.mem.eql(u8, backend, "sdl_renderer")) {
        current_renderer = .SdlRenderer;
    } else if (std.mem.eql(u8, backend, "sdl_gpu")) {
        current_renderer = .SdlGpu;
    } else {
        std.log.err("Unknown backend: {s}", .{backend});
        return error.UnknownBackend;
    }

    // 初始化状态
    var state = try State.init(allocator);
    defer state.deinit();

    // 在不同后端循环渲染（模式切换）
    while (current_renderer != null) {
        if (current_renderer == .SdlRenderer) {
            if (try renderer.render(allocator, &state) == .toggle) {
                current_renderer = .SdlGpu;
            } else {
                current_renderer = null;
            }
        } else if (current_renderer == .SdlGpu) {
            if (try renderer_gpu.render(allocator, &state) == .toggle) {
                current_renderer = .SdlRenderer;
            } else {
                current_renderer = null;
            }
        }
    }
}
