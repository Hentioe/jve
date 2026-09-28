const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const viewer = @import("imageviewer");

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    // 根据编译模式选择内存分配器
    const allocator, const is_debug = switch (builtin.mode) {
        .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
        .ReleaseFast, .ReleaseSmall => .{ std.heap.c_allocator, false },
    };
    defer if (is_debug) {
        std.debug.assert(debug_allocator.deinit() == .ok);
    };
    // 解析命令行参数
    const res = try cli.init(allocator);
    defer res.deinit();
    // 图片路径（带默认值）
    var file_path: []const u8 = "image.png";
    if (res.positionals[0]) |pos| {
        file_path = pos;
    }
    // 初始化
    defer viewer.deinit();
    try viewer.init(allocator, file_path);
    // 读取后端参数
    const backend: []const u8 = res.args.backend orelse viewer.config.get().default_mode;
    std.log.info("Using backend: {s}", .{backend});
    // 渲染图像
    try viewer.render(allocator, backend);
}
