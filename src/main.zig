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
    } else if (res.args.@"clear-cache" != 0) { // 执行缓存清理
        try jve.clearCache(allocator, res.args.config);
    } else if (res.positionals[0]) |file_path| { // 取位置参数作为路径
        // 启动跟踪
        var trace = jve.StepTrace.init(allocator);
        defer trace.deinit();
        defer trace.report(); // 输出跟踪报告
        // 初始化
        defer jve.deinit();
        try jve.init(allocator, &trace, file_path, res.args.config);
        // 显示图像
        try jve.show(allocator, res.args.display);
    } else if (res.args.display) |d| (if (std.mem.eql(u8, d, "diag")) {
        // 显示诊断模式
        try jve.display_init(allocator);
        defer jve.display_deinit();
        try jve.showDiag(allocator);
    }) else {
        // 显示欢迎模式
        try jve.display_init(allocator);
        defer jve.display_deinit();
        try jve.showWelcome(allocator);
    }
}
