const std = @import("std");
const builtin = @import("builtin");
const jve = @import("jve");
const cli = @import("cli.zig");

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
    if (res.args.supports != 0) {
        // 获取并打印支持的图像格式
        try jve.vips_init(allocator);
        defer jve.vips_deinit();
        const formats = try std.mem.join(allocator, " ", try jve.vips.formats.get());
        defer allocator.free(formats);
        std.debug.print("Supported formats: {s}\n", .{formats});
    } else if (res.positionals[0]) |file_path| { // 取位置参数作为路径
        // 初始化
        defer jve.deinit();
        try jve.init(allocator, file_path, res.args.config);
        // 显示模式
        const display_mode: []const u8 = res.args.display orelse jve.config.get().display_mode;
        // 显示图像
        try jve.show(display_mode);
    } else {
        try jve.display_init();
        defer jve.display_deinit();
        try jve.showWelcome(allocator);
    }
}
