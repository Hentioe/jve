const std = @import("std");
const builtin = @import("builtin");
const jve = @import("jve");
const cli = @import("cli.zig");
const StepTrace = jve.StepTrace;
const Subsystems = jve.Subsystems;

pub fn main(init: std.process.Init) !void {
    // 根据编译模式选择内存分配器
    const allocator = switch (builtin.mode) {
        .debug, .safe => init.gpa, // 通常是 SafeAllocator
        .fast, .small => std.heap.c_allocator,
    };

    // 构建子系统的初始化选项
    var opts = Subsystems.buildOpts(init);
    // 解析命令行参数
    const res = try cli.init(allocator, init.minimal.args);
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
        var trace = StepTrace.init(allocator, "startup");
        defer trace.deinit();
        defer trace.report();
        // 附加子系统参数
        opts.file_path = file_path;
        opts.config_path = res.args.config;
        // 初始化全部子系统
        defer Subsystems.deinit(Subsystems.all);
        try Subsystems.init(Subsystems.all, allocator, opts, &trace);
        // 显示图片
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
