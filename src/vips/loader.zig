const std = @import("std");
const c = @import("c.zig").c;
const formats = @import("formats.zig");
const Error = @import("errors.zig").Error;
const Image = @import("Image.zig");
const IShape = @import("../root.zig").IShape;

pub const LoadedImage = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8, // 涉及内存申请
    file_name: []const u8, // file_path 的切片
    shape: IShape(i32), // 宽/高/通道数
    format: i32,
    size: usize,
    pixels_ptr: [*c]c_ushort, // 像素数据的指针
    _out: Image.Out, // 持有像素数据内存，负责安全回收

    pub fn deinit(self: *LoadedImage) void {
        self.allocator.free(self.file_path);
        self._out.deinit();
        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator, path: []const u8) Error!LoadedImage {
    // 获取扩展名
    const extension = std.fs.path.extension(path);
    if (!try formats.isSupported(extension)) return Error.UnsupportedFormat; // 主动检查格式是否支持

    // 从文件创建图像（initFromFile 内部已转换为 sRGB）
    var image = try Image.initFromFile(allocator, path);
    defer image.deinit();

    // 转换为 RGBA（已有 alpha 通道时内部会跳过）
    try image.addAlpha(255.0);
    // 提取像素数据
    var out = try image.allocOutInMemory();
    errdefer out.deinit();

    // 将外部传入的 path 复制一遍
    const file_path = try allocator.alloc(u8, path.len);
    @memcpy(file_path, path);

    return LoadedImage{
        .allocator = allocator,
        .file_path = file_path,
        .file_name = std.fs.path.basename(file_path),
        .shape = .{ .w = image.width, .h = image.height, .c = image.channels },
        .format = @intFromEnum(image.format),
        .size = out.data_size,
        .pixels_ptr = @ptrCast(@alignCast(out.data_ptr)),
        ._out = out,
    };
}
