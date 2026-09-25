const std = @import("std");
const cli = @import("cli.zig");
const imageviewer = @import("imageviewer");

pub fn main() !void {
    // 创建内存分配器
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit(); // todo: 输出检查结果
    const allocator = gpa.allocator();
    // 解析命令行参数
    const res = try cli.init(allocator);
    defer res.deinit();
    // 图片路径（带默认值）
    var file_path: []const u8 = "image.png";
    if (res.positionals[0]) |pos| {
        file_path = pos;
    }
    // 初始化
    defer imageviewer.deinit(); // 避免因 initialize 崩溃而未能释放资源
    try imageviewer.init(allocator, file_path);
    // 读取后端参数
    const backend: []const u8 = res.args.backend orelse "sdl_renderer";
    std.log.info("Using backend: {s}", .{backend});
    // 渲染图像
    try imageviewer.render(allocator, backend);
}
