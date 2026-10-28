const std = @import("std");
const Io = std.Io;
const OpenUrlError = @import("errors.zig").OpenUrlError;

/// 用系统默认浏览器打开 URL（Linux，依赖 xdg-open）
/// 必须传入持有真实分配器的 `Io`：`std.process.spawn` 内部会分配 argv/env，
/// 而 `global_single_threaded` 的分配器是 `Allocator.failing`，会直接返回 `OutOfMemory`。
pub fn open(runtime_io: Io, url: []const u8) OpenUrlError!void {
    var child = try std.process.spawn(runtime_io, .{
        .argv = &.{ "xdg-open", url },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });

    const term = try child.wait(runtime_io);
    switch (term) {
        .exited => |code| if (code != 0) return OpenUrlError.OpenUrlFailed,
        else => return OpenUrlError.OpenUrlFailed,
    }
}
