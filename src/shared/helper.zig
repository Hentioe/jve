const std = @import("std");
const Allocator = std.mem.Allocator;
const errors = @import("errors.zig");
const OpenUrlError = errors.OpenUrlError;

// 输入一个路径，检查是否存在
pub fn pathExists(path: []const u8) bool {
    const cwd = std.fs.cwd();
    cwd.access(path, .{}) catch |err| {
        if (err == std.fs.Dir.AccessError.FileNotFound) {
            return false;
        }
    };
    return true;
}

// 输入一个路径，检查是否可访问
pub fn pathAccessible(path: []const u8) bool {
    const cwd = std.fs.cwd();
    cwd.access(path, .{}) catch |err| {
        std.log.warn("Failed to access path: {}", .{err});
        return false;
    };
    return true;
}

pub fn strdup(s: []const u8) Allocator.Error![*:0]u8 {
    const buf = try std.heap.raw_c_allocator.dupeZ(u8, s);
    return buf.ptr;
}

/// 用系统默认浏览器打开 URL（Linux，依赖 xdg-open）
pub fn openUrl(allocator: Allocator, url: []const u8) OpenUrlError!void {
    var child = std.process.Child.init(&.{ "xdg-open", url }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return OpenUrlError.OpenUrlFailed,
        else => return OpenUrlError.OpenUrlFailed,
    }
}
