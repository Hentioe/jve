const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config.zig");
const vips = @import("vips");
const Allocator = std.mem.Allocator;
const writer = vips.writer;
const LImage = vips.LImage;
const extractor = @import("extractor.zig");
const clipboard = @import("clipboard.zig");
const Self = @This();

pub const Error = extractor.Error || vips.Error || config.Error || std.mem.Allocator.Error || error{CreateScreenshotDirFailed};

allocator: Allocator,
extracted: extractor.Extracted,
image: *const LImage,

pub fn init(allocator: std.mem.Allocator, gpu: *const sdl.Gpu, texture: ?*sdl.GPUTexture, image: *const LImage) Error!Self {
    // 提取并下载纹理像素数据
    const extracted = try extractor.extract(allocator, gpu, texture, image.shape.to(u32));

    return Self{
        .allocator = allocator,
        .extracted = extracted,
        .image = image,
    };
}

pub fn deinit(self: *Self) void {
    self.extracted.deinit();
    self.* = undefined;
}

pub fn saveToFile(self: *const Self) Error!void {
    // 用 sfa 处理路径分配（大概 3 条）
    var sfa = std.heap.stackFallback(256 * 3, self.allocator);
    const a = sfa.get();
    // 创建输出文件路径
    const outfile = try allocOutfile(a, self.image.file_name);
    defer a.free(outfile);
    const outfile_z = try a.dupeZ(u8, outfile);
    defer a.free(outfile_z);
    // 写入到文件
    const data = self.extracted.data;
    try writer.savePixelsToFile(data.ptr, self.image.shape, outfile_z);
    // 输出消息：截图已保存到：outfile
    std.log.info("Screenshot saved to: {s} ({d}KB)", .{ outfile, shared.helper.bytesToKb(data.len) });
}

// todo: 不要在函数内部输出日志，直接返回错误
/// 复制到剪切板
pub fn copyToClipboard(self: *const Self) void {
    const pixels_ptr = self.extracted.data.ptr;
    // 创建编码器
    var encoder = writer.Encoder.init(pixels_ptr, self.image.shape);
    defer encoder.deinit();
    // 编码图片
    if (encoder.encode()) {
        // 复制到剪切板
        if (clipboard.copyImage(self.allocator, encoder.encoded.?, .png)) {
            std.log.info("Screenshot copied to clipboard, format: {s}", .{"png"});
        } else |err| {
            std.log.err("Failed to copy screenshot to clipboard: {}", .{err});
        }
    } else |err| {
        std.log.err("Failed to encode screenshot: {}", .{err});
    }
}

/// 分配输出文件名（路径），基于原始文件名和当前时间戳。
fn allocOutfile(allocator: Allocator, original_name: []const u8) Error![]u8 {
    // 取文件名主干：去掉目录和最后一个扩展名
    const stem = std.fs.path.stem(original_name);
    const ts = std.time.timestamp(); // 秒级 Unix 时间戳（i64）
    const new_name = try std.fmt.allocPrint(allocator, "{s}_{d}.{f}", .{ stem, ts, config.get().screenshot.format });

    // 将文件名与配置中的截图保存目录拼接为完整路径
    if (config.get().screenshot.dir) |dir| {
        defer allocator.free(new_name); // 释放文件名
        // 获取输出目录
        const out_dir = try config.allocFullPath(allocator, dir);
        // 创建输出目录
        std.fs.cwd().makePath(out_dir) catch return Error.CreateScreenshotDirFailed;
        // 创建完整文件路径
        return try std.fs.path.join(allocator, &.{ out_dir, new_name });
    } else {
        return new_name;
    }
}
