const std = @import("std");
const cli = @import("cli.zig");
const imageviewer = @import("root.zig");

pub fn main() !void {
    // 内存分配器
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    // 解析命令行参数
    const res = try cli.parse(allocator);
    defer res.deinit();
    // 图片路径（带默认值）
    var file_path: []const u8 = "image.png";
    if (res.positionals[0]) |pos| {
        file_path = pos;
    }
    // 载入图像
    const loaded = try imageviewer.loadImage(allocator, file_path);
    // 输出基本信息
    std.debug.print("Image width: {}\n", .{loaded.width});
    std.debug.print("Image height: {}\n", .{loaded.height});
    std.debug.print("Image bands: {}\n", .{loaded.bands});
    // 渲染图像
    try imageviewer.renderImage(allocator, loaded);
}
