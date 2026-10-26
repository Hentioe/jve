const std = @import("std");
const cli = @import("cli.zig");
const jve = @import("jve");
const StepTrace = jve.StepTrace;
const Subsystems = jve.Subsystems;

pub fn main(init: std.process.Init) !void {
    // 解析命令行参数
    const res = try cli.init(init.gpa, init.minimal.args);
    defer res.deinit();
    // 构造子系统启动器
    var subsystems = Subsystems.init(init);
    defer subsystems.deinit();
    if (res.args.supports != 0) { // 输出所支持的图像格式列表
        // 启动子系统（仅 vips）
        subsystems.fillSystems(.initOne(.vips));
        try subsystems.start();
        // 打印格式列表
        const formats = try std.mem.join(init.gpa, " ", try jve.vips.formats.get());
        defer init.gpa.free(formats);
        std.debug.print("Supported formats: {s}\n", .{formats});
    } else if (res.args.@"clear-cache" != 0) { // 执行缓存清理
        try jve.clearCache(init.gpa, res.args.config);
    } else if (res.positionals[0]) |file_path| { // 取位置参数作为路径
        // 装载全部子系统
        subsystems.fillSystems(Subsystems.all);
        // 子系统参数
        var trace = StepTrace.init(try .buffer(99), "startup"); // 性能跟踪
        defer trace.report();
        subsystems.opts.trace = &trace;
        subsystems.opts.file_path = file_path;
        subsystems.opts.config_path = res.args.config;
        // 启动子系统
        try subsystems.start();
        // 显示图片
        try jve.show(init.gpa, res.args.display);
    } else if (res.args.display) |d| (if (std.mem.eql(u8, d, "diag")) {
        // 启动子系统（基本显示）
        subsystems.fillSystems(.initMany(&.{ .app_env, .ui, .display }));
        try subsystems.start();
        // 显示诊断模式
        try jve.showDiag(init.gpa);
    }) else {
        // 启动子系统（基本显示）
        subsystems.fillSystems(.initMany(&.{ .app_env, .ui, .display }));
        try subsystems.start();
        // 显示欢迎界面
        try jve.showWelcome(init.gpa);
    }
}
