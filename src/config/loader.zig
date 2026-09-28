const std = @import("std");
const paths = @import("paths.zig");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;
const Error = errors.Error;

pub fn load(allocator: Allocator, config_path: ?[]const u8) Error!void {
    const path = if (config_path) |path| path else val: {
        break :val try paths.findConfigFile(allocator, "imageviewer", "imageviewer.toml");
    };

    defer if (path) |p| {
        if (config_path == null) allocator.free(p);
    };

    // todo: 如果存在配置文件，解析它。否则返回默认配置。

    if (path) |p| {
        std.log.info("Loading config file: {s}", .{p});
    }
}
