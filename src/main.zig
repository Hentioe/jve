const std = @import("std");
const cli = @import("cli.zig");
const imageviewer = @import("root.zig");

pub fn main() !void {
    // 内存分配器
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    // 解析命令行参数
    const res = try cli.init(allocator);
    defer res.deinit();
    // 图片路径（带默认值）
    var file_path: []const u8 = "image.png";
    if (res.positionals[0]) |pos| {
        file_path = pos;
    }
    // 载入图像
    const loaded = try imageviewer.loader.load(file_path);
    // 输出基本信息
    std.log.info("Image size: {d}x{d}", .{ loaded.width, loaded.height });
    // 读取后端参数
    const backend: []const u8 = res.args.backend orelse "sdl_renderer";
    std.log.info("Using backend: {s}", .{backend});
    // 渲染图像
    if (std.mem.eql(u8, backend, "sdl_renderer")) {
        try imageviewer.renderer.render(allocator, loaded);
    } else if (std.mem.eql(u8, backend, "sdl_gpu")) {
        try imageviewer.renderer_gpu.render(allocator, loaded);
    } else {
        std.log.err("Unknown backend: {s}", .{backend});
        return error.UnknownBackend;
    }
}
