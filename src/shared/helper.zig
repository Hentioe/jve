const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const errors = @import("errors.zig");
const OpenUrlError = errors.OpenUrlError;

const io = std.Io.Threaded.global_single_threaded.io();

// 输入一个路径，检查是否存在
pub fn pathExists(path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch |err| {
        if (err == std.Io.Dir.AccessError.FileNotFound) return false;
    };
    return true;
}

// 输入一个路径，检查是否可访问
pub fn pathAccessible(path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch |err| {
        std.log.warn("Failed to access path: {}", .{err});
        return false;
    };
    return true;
}

pub fn strdup(s: []const u8) Allocator.Error![*:0]u8 {
    const buf = try std.heap.c_allocator.dupeSentinel(u8, s, 0);
    return buf.ptr;
}

/// 数据大小单位
pub const DataSizeUnit = enum { kb };
/// 字节转到指定单位，直接截断小数部分。
pub fn bytesTo(unit: DataSizeUnit, bytes: u64) u64 {
    return switch (unit) {
        .kb => bytes / 1024,
    };
}

/// 用系统默认浏览器打开 URL（Linux，依赖 xdg-open）
pub fn openUrl(url: []const u8) OpenUrlError!void {
    var child = try std.process.spawn(io, .{
        .argv = &.{ "xdg-open", url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return OpenUrlError.OpenUrlFailed,
        else => return OpenUrlError.OpenUrlFailed,
    }
}

/// 当前 Unix 毫秒时间戳(挂钟时间,可能被 NTP 调整,不保证单调)
pub fn milliTimestamp() i64 {
    const now = std.Io.Clock.real.now(io);
    return @intCast(now.toMilliseconds());
}

/// 当前 Unix 秒级时间戳(挂钟时间,可能被 NTP 调整,不保证单调)
pub fn timestamp() i64 {
    return Io.Clock.real.now(io).toSeconds();
}
