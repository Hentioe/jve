const std = @import("std");

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
