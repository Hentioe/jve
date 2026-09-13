const std = @import("std");
const imageviewer = @import("root.zig");

pub fn main() !void {
    // 载入图像
    const loaded = try imageviewer.loadImage(std.heap.page_allocator, "image.png");
    defer loaded.deinit();
    // 输出基本信息
    std.debug.print("Image width: {}\n", .{loaded.width});
    std.debug.print("Image height: {}\n", .{loaded.height});
    std.debug.print("Image bands: {}\n", .{loaded.bands});
    // 渲染图像
    try imageviewer.renderImage(loaded);
}
