const std = @import("std");
const errors = @import("errors.zig");
const vips_format = @import("vips/format.zig");
const VipsError = @import("vips/errors.zig").Error;
const Backend = @import("sdl/enums.zig").Backend;
const Allocator = std.mem.Allocator;

pub const config = @import("config.zig");
pub const vips = @import("vips.zig");
pub const sdl = @import("sdl.zig");
pub const album = @import("album.zig");
pub const loader = @import("vips/loader.zig");
pub const writer = @import("vips/writer.zig");
pub const renderer = @import("sdl/renderer.zig");
pub const renderer_gpu = @import("sdl/renderer_gpu.zig");
pub const State = @import("sdl/State.zig");
pub const clipboard = @import("clipboard.zig");
pub const LoadError = errors.LoadError;

pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !void {
    try config.init(allocator, "./imageviewer.toml");
    try vips.init(allocator);
    try album.init(allocator, file_path);
    try sdl.init();
}

pub fn deinit() void {
    // 和 init 的顺序相反，先 deinit 后初始化的组件
    sdl.deinit();
    album.deinit();
    vips.deinit();
    config.deinit();
}

pub fn isSupported(suffix: []const u8) !bool {
    return try vips_format.isSupported(suffix);
}

pub fn extensions() ![]const []const u8 {
    return try vips_format.extensions();
}

pub fn load(allocator: Allocator, file_path: []const u8) LoadError!loader.Image {
    // 检查文件的可访问性
    const stat = std.fs.cwd().statFile(file_path) catch |err| return err;
    // 检查输入是否为文件
    if (stat.kind != .file) return LoadError.NotAFile;
    return try loader.load(allocator, file_path);
}

pub fn render(allocator: Allocator, backend: []const u8) !void {
    var current_renderer: ?Backend = null;
    if (std.mem.eql(u8, backend, "sdl_renderer")) {
        current_renderer = .sdl_renderer;
    } else if (std.mem.eql(u8, backend, "sdl_gpu")) {
        current_renderer = .sdl_gpu;
    } else {
        std.log.err("Unknown backend: {s}", .{backend});
        return error.UnknownBackend;
    }

    // 初始化状态
    var state = try State.init(allocator);
    defer state.deinit();

    // 在不同后端循环渲染（模式切换）
    while (current_renderer != null) {
        if (current_renderer == .sdl_renderer) {
            if (try renderer.render(allocator, &state) == .toggle) {
                current_renderer = .sdl_gpu;
            } else {
                current_renderer = null;
            }
        } else if (current_renderer == .sdl_gpu) {
            if (try renderer_gpu.render(allocator, &state) == .toggle) {
                current_renderer = .sdl_renderer;
            } else {
                current_renderer = null;
            }
        }
    }
}
