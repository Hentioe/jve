const std = @import("std");
const c = @import("sdl").c;
const config = @import("config");
const vips = @import("vips");
const writer = vips.writer;
const LImage = vips.LImage;
const clipboard = @import("clipboard.zig");
const Allocator = std.mem.Allocator;
const extractor = @import("extractor.zig");
const Gpu = @import("sdl").Gpu;
const Self = @This();

pub const Error = extractor.Error || vips.Error || config.Error || std.mem.Allocator.Error || error{CreateScreenshotDirFailed};

allocator: Allocator,
extracted: extractor.Extracted,
image: *const LImage,

pub fn init(allocator: std.mem.Allocator, gpu: *const Gpu, texture: ?*c.SDL_GPUTexture, image: *const LImage) Error!Self {
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
    var sf = std.heap.stackFallback(256 * 3, self.allocator);
    const sfa = sf.get();
    // 创建输出文件路径
    const out_filename = try allocOutFilename(sfa, self.image.file_name, "png");
    defer sfa.free(out_filename);
    const filename = try sfa.dupeZ(u8, out_filename);
    // 写入到文件
    try writer.savePixelsToFile(self.extracted.data.ptr, self.image.shape, filename);
    std.log.info("Screenshot saved, size: {d}", .{self.extracted.data.len});
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
fn allocOutFilename(allocator: Allocator, original_file_name: []const u8, format: []const u8) Error![]u8 {
    // 取文件名主干：去掉目录和最后一个扩展名
    const stem = std.fs.path.stem(original_file_name);
    // 兼容 ".png" 这种带点的格式写法
    const ext = if (format.len > 0 and format[0] == '.') format[1..] else format;
    const ts = std.time.timestamp(); // 秒级 Unix 时间戳（i64）
    const new_filename = try std.fmt.allocPrint(allocator, "{s}_{d}.{s}", .{ stem, ts, ext });

    // 将文件名与配置中的截图保存目录拼接为完整路径
    if (config.get().screenshot_dir) |screenshot_dir| {
        defer allocator.free(new_filename); // 释放文件名
        // 获取输出目录
        const out_dir = try config.allocFullPath(allocator, screenshot_dir);
        // 创建输出目录
        std.fs.cwd().makePath(out_dir) catch |err| {
            std.log.err("Failed to create screenshot directory: {}", .{err});
            return Error.CreateScreenshotDirFailed;
        };
        // 创建完整文件路径
        return try std.fs.path.join(allocator, &.{ out_dir, new_filename });
    } else {
        return new_filename;
    }
}
