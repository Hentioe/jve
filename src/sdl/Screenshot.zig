const std = @import("std");
const c = @import("c.zig").c;
const root = @import("../root.zig");
const config = root.config;
const writer = root.writer;
const LImage = root.loader.LoadedImage;
const clipboard = @import("clipboard.zig");
const Allocator = std.mem.Allocator;
const Extractor = @import("Extractor.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
extracted: Extractor,
image: *const LImage,

pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, texture: ?*c.SDL_GPUTexture, image: *const LImage) Error!Self {
    // 创建下载器
    var extractor = Extractor.init(allocator, device, image.shape);
    errdefer extractor.deinit();
    // 下载纹理
    try extractor.downloadTexture(texture);

    return Self{
        .allocator = allocator,
        .extracted = extractor,
        .image = image,
    };
}

pub fn deinit(self: *Self) void {
    self.extracted.deinit();
    self.* = undefined;
}

pub fn saveToFile(self: *const Self) void {
    if (!self.extracted.downloaded) {
        std.log.err("Screenshot not downloaded yet", .{});
        return;
    }
    const out_filename = allocNewName(self.allocator, self.image.file_name, "png") catch |err| {
        std.log.err("Failed to create new filename: {}", .{err});
        return;
    };
    defer self.allocator.free(out_filename);
    // 若配置了截图保存目录，则拼接为完整路径；否则直接使用文件名
    const joined = joinOutputPath(self.allocator, out_filename) catch |err| {
        std.log.err("Failed to resolve screenshot path: {}", .{err});
        return;
    };
    defer if (joined) |p| self.allocator.free(p);
    // 写入到文件
    if (writer.savePixelsToFile(
        self.extracted.pixels_slice.ptr,
        self.image.shape,
        joined orelse out_filename,
    )) {
        std.log.info("Screenshot saved, size: {d}", .{self.extracted.buffer_size});
    } else |err| {
        std.log.err("Failed to save screenshot: {}", .{err});
    }
}

/// 复制到剪切板
pub fn copyToClipboard(self: *const Self) void {
    if (!self.extracted.downloaded) {
        std.log.err("Screenshot not downloaded yet", .{});
        return;
    }
    const pixels_ptr = self.extracted.pixels_slice.ptr;
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

/// 将文件名与配置中的截图保存目录拼接为完整路径。
/// 未配置目录时返回 null（无需分配）；目录不存在时尝试创建，失败则退回当前目录。
fn joinOutputPath(allocator: Allocator, filename: []const u8) Error!?[]u8 {
    const dir = config.get().screenshot_dir orelse return null;
    std.fs.cwd().makePath(dir) catch |err| {
        std.log.warn("Cannot create screenshot directory '{s}': {}, saving to current directory", .{ dir, err });
        return null;
    };
    return try std.fs.path.join(allocator, &.{ dir, filename });
}

/// 分配一个新的文件名，基于原始文件名和当前时间戳。
fn allocNewName(allocator: Allocator, original_file_name: []const u8, format: []const u8) Error![]u8 {
    // 取文件名主干：去掉目录和最后一个扩展名
    const stem = std.fs.path.stem(original_file_name);
    // 兼容 ".png" 这种带点的格式写法
    const ext = if (format.len > 0 and format[0] == '.') format[1..] else format;
    const ts = std.time.timestamp(); // 秒级 Unix 时间戳（i64）
    return std.fmt.allocPrint(allocator, "{s}_{d}.{s}", .{ stem, ts, ext });
}
