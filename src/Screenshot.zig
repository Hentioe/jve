const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const CString = shared.CString;
const bytesTo = shared.h.bytesTo;
const config = @import("config.zig");
const vips = @import("vips");
const Allocator = std.mem.Allocator;
const writer = vips.writer;
const LImage = vips.LImage;
const extractor = @import("extractor.zig");
const clipboard = @import("clipboard.zig");
const Self = @This();

pub const Error = error{CreateScreenshotDirFailed} || CString.Error || extractor.Error || vips.Error || config.Error || std.mem.Allocator.Error;
pub const Action = enum { save, copy, none };

const io = std.Io.Threaded.global_single_threaded.io();

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

const Saved = struct {
    filepath: CString,
    size_kb: u64,
};

pub fn saveToFile(self: *const Self) Error!Saved {
    var arena_state = std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    // 生成输出文件路径
    const filename = try CString.fromPath(try generateOutfileName(arena, self.image.file_name));
    // 写入到文件
    const data = self.extracted.data;
    try writer.saveToFile(data.ptr, self.image.shape, filename.data());
    return .{
        .filepath = filename,
        .size_kb = bytesTo(.kb, data.len),
    };
}

/// 复制到剪切板（目前仅支持 PNG）
pub fn copyToClipboard(self: *const Self) Error!void {
    // 创建编码器
    var encoder = writer.Encoder.init(.png);
    // 编码图片
    const data_ptr = self.extracted.data.ptr;
    const encoded = try encoder.encode(data_ptr, self.image.shape);
    // 复制到剪切板
    try clipboard.copyImage(self.allocator, encoded.data, .png);
}

/// 生成一个输出文件名（路径），基于原始文件名和当前时间戳。
fn generateOutfileName(arena: Allocator, original_name: []const u8) Error![]u8 {
    // 取文件名主干：去掉目录和最后一个扩展名
    const stem = std.fs.path.stem(original_name);
    const ts = shared.timestamp(); // 秒级 Unix 时间戳（i64）
    const name = try std.fmt.allocPrint(arena, "{s}_{d}.{f}", .{ stem, ts, config.get().screenshot.format });

    // 将文件名与配置中的截图保存目录拼接为完整路径
    if (config.get().screenshot.dir) |dir| {
        // 获取输出目录
        const out_dir = try config.allocFullPath(arena, dir);
        // 创建输出目录
        std.Io.Dir.cwd().createDirPath(io, out_dir) catch return Error.CreateScreenshotDirFailed;
        // 创建完整文件路径
        return try std.fs.path.join(arena, &.{ out_dir, name });
    } else {
        return name;
    }
}
