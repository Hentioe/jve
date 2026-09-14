const std = @import("std");
const imageviewer = @import("root.zig");

pub fn main() !void {
    // 内存分配器
    const allocator = std.heap.page_allocator;
    // 载入图像
    const loaded = try imageviewer.loadImage(allocator, "image.jpeg");
    defer loaded.deinit();
    // 输出基本信息
    std.debug.print("Image width: {}\n", .{loaded.width});
    std.debug.print("Image height: {}\n", .{loaded.height});
    std.debug.print("Image bands: {}\n", .{loaded.bands});
    // 渲染图像
    try imageviewer.renderImage(allocator, loaded);
}
