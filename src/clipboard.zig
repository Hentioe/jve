// 此实现并未实际使用：已被 src/sdl/clipboard.zig 实现取代
const std = @import("std");
const enums = @import("enums.zig");
const ScreenshotFormat = enums.ScreenshotFormat;
const Allocator = std.mem.Allocator;

pub const Error = error{
    NoClipboardBackend,
    ClipboardToolFailed,
};

// 写入剪贴板，MIME 由调用方指定（如 "image/png"、"image/jpeg"）
pub fn copyImage(allocator: Allocator, data: []const u8, format: ScreenshotFormat) !void {
    const wayland = envNonEmpty("WAYLAND_DISPLAY");
    const x11 = envNonEmpty("DISPLAY");
    if (!wayland and !x11) return Error.NoClipboardBackend;
    const mime = switch (format) {
        .png => "image/png",
    };

    var tool_failed = false;

    if (wayland) {
        if (pipeTo(allocator, &.{ "wl-copy", "--type", mime }, data)) |_| {
            return;
        } else |err| switch (err) {
            Error.ClipboardToolFailed => tool_failed = true,
            else => return err,
        }
    }

    if (x11) {
        if (pipeTo(allocator, &.{ "xclip", "-selection", "clipboard", "-t", mime, "-i" }, data)) |_| {
            return;
        } else |err| switch (err) {
            Error.ClipboardToolFailed => tool_failed = true,
            else => return err,
        }
    }

    return if (tool_failed) Error.ClipboardToolFailed else Error.NoClipboardBackend;
}

fn envNonEmpty(name: []const u8) bool {
    const v = std.posix.getenv(name) orelse return false;
    return v.len > 0;
}

fn pipeTo(allocator: Allocator, argv: []const []const u8, data: []const u8) Error!void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Pipe;
    // 这两个工具读完 stdin 后会 fork 到后台持有剪贴板，
    // 后台进程继承 stdout/stderr，用 Pipe 去读会一直阻塞。
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch |err| {
        std.log.err("Failed to spawn clipboard tool: {}", .{err});
        return Error.ClipboardToolFailed;
    };

    const write_result = child.stdin.?.writeAll(data);
    child.stdin.?.close();
    child.stdin = null; // 避免 wait() 再关一次

    const term = child.wait() catch |err| {
        std.log.err("Failed to wait for clipboard tool: {}", .{err});
        return Error.ClipboardToolFailed;
    };

    write_result catch return Error.ClipboardToolFailed;
    switch (term) {
        .Exited => |code| if (code != 0) return Error.ClipboardToolFailed,
        else => return Error.ClipboardToolFailed,
    }
}
