const std = @import("std");
const c = @import("c.zig").c;
const root = @import("../root.zig");
const Image = root.loader.Image;
const writer = root.writer;
const clipboard = @import("clipboard.zig");
const Allocator = std.mem.Allocator;
const Extractor = @import("Extractor.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
extractor: Extractor,
image: *const Image,

pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, texture: ?*c.SDL_GPUTexture, image: *const Image) Error!Self {
    // 创建下载器
    var extractor = Extractor.init( // todo: 重构下载器，init 函数不再传递图片信息
        allocator,
        device,
        image.width,
        image.height,
        image.bands,
    );
    // 下载纹理
    try extractor.downloadTexture(texture);

    return Self{
        .allocator = allocator,
        .extractor = extractor,
        .image = image,
    };
}

pub fn deinit(self: *Self) void {
    self.extractor.deinit();
    self.* = undefined;
}

pub fn saveToFile(self: *const Self) void {
    if (!self.extractor.downloaded) {
        std.log.err("Screenshot not downloaded yet", .{});
        return;
    }
    const out_filename = createNewName(self.allocator, self.image.file_name, "png") catch |err| {
        std.log.err("Failed to create new filename: {}", .{err});
        return;
    };
    defer self.allocator.free(out_filename);
    // 写入到文件
    if (writer.savePixelsToFile(
        self.extractor.pixels_slice.ptr,
        self.image.width,
        self.image.height,
        self.image.bands,
        out_filename,
    )) {
        std.log.info("Screenshot saved, size: {d}", .{self.extractor.buffer_size});
    } else |err| {
        std.log.err("Failed to save screenshot: {}", .{err});
    }
}

// 复制到剪切板
pub fn copyToClipboard(self: *const Self) void {
    if (!self.extractor.downloaded) {
        std.log.err("Screenshot not downloaded yet", .{});
        return;
    }
    // 创建编码器
    var encoder = writer.Encoder.init(
        self.extractor.pixels_slice.ptr,
        self.image.width,
        self.image.height,
        self.image.bands,
    );
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

fn createNewName(allocator: Allocator, original_file_name: []const u8, format: []const u8) Error![]u8 {
    // 取文件名主干：去掉目录和最后一个扩展名
    const stem = std.fs.path.stem(original_file_name);
    // 兼容 ".png" 这种带点的格式写法
    const ext = if (format.len > 0 and format[0] == '.') format[1..] else format;
    const ts = std.time.timestamp(); // 秒级 Unix 时间戳（i64）
    return std.fmt.allocPrint(allocator, "{s}_{d}.{s}", .{ stem, ts, ext });
}
