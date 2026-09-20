const std = @import("std");
const root = @import("root.zig");
const loader = root.loader;
const Image = loader.Image;
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");

pub const Error = error{
    CacheNotInitialized,
    NoImageSelected,
    InvalidPath,
    ImageLoadFailed,
};

// 全局缓存
const Cache = struct {
    gpa: Allocator,
    scanner: Scanner,
    image: Image,
    dirty: bool,
    full_path: ?[]const u8 = null,

    pub fn deinit(self: *Cache) void {
        self.image.deinit();
        self.scanner.deinit();
        if (self.full_path) |full_path| self.gpa.free(full_path);
        self.* = undefined;
    }

    pub fn updateFullPath(self: *Cache, path: []const u8) void {
        if (self.full_path) |full_path| self.gpa.free(full_path);
        self.full_path = path;
    }
};
var global: ?Cache = null;

inline fn cached() Error!*Cache {
    if (global) |*cache| {
        return cache;
    } else {
        return Error.CacheNotInitialized;
    }
}

/// 全局的初始化函数
/// 扫描文件所在目录，并定位到该文件；文件不在结果中时停在第一个
pub fn initialize(gpa: Allocator, file_path: []const u8) !void {
    const dir = std.fs.path.dirname(file_path) orelse ".";
    const base = std.fs.path.basename(file_path);
    var scanner = try Scanner.init(gpa, dir, try root.extensions());
    // 选择当前文件
    _ = scanner.select(base);
    // 加载图片
    const image = try loader.load(file_path);
    // 输出图像信息
    std.log.info("Current image: {s}", .{base});
    std.log.info("Image size: {d}x{d}", .{ image.width, image.height });
    global = Cache{
        .gpa = gpa,
        .scanner = scanner,
        .image = image,
        .dirty = false,
        // 初始化的路径不要保存，cli 会负责回收
    };
}

/// 全局的关闭函数
pub fn shutdown() void {
    if (global) |*cache| {
        cache.deinit();
        global = null;
    }
}

pub fn next() Error!?[]const u8 {
    std.log.info("Going to next image", .{});
    var cache = try cached();
    cache.dirty = true;
    return cache.scanner.next();
}

pub fn prev() Error!?[]const u8 {
    std.log.info("Going to previous image", .{});
    var cache = try cached();
    cache.dirty = true;
    return cache.scanner.prev();
}

fn reloadCurrent() Error!void {
    std.log.info("Reloading current image", .{});
    var cache = try cached();
    if (cache.scanner.current()) |file_name| {
        // 如果有图片，释放它
        cache.image.deinit();
        // 组合成文件路径
        const dir_path = cache.scanner.dir_path;
        const full_path = std.fs.path.join(cache.gpa, &[_][]const u8{ dir_path, file_name }) catch |err| {
            std.log.err("Failed to join path: {}", .{err});
            return Error.InvalidPath;
        };
        // 更新缓存中的路径（后续释放需要）
        cache.updateFullPath(full_path);
        // 加载图片
        const image = loader.load(full_path) catch |err| {
            std.log.err("Failed to load image: {}", .{err});
            return Error.ImageLoadFailed;
        };
        // 缓存图片
        cache.image = image;
        std.log.info("Current image: {s}", .{image.file_name});
        // 标记缓存为干净
        cache.dirty = false;
    } else {
        // 没有选择图片
        return Error.NoImageSelected;
    }
}

pub fn current() Error!Image {
    const c = try cached();
    if (c.dirty) { // 如果缓存脏了，重新加载当前图片
        std.log.info("Cache is dirty, reloading current image", .{});
        try reloadCurrent();
    }
    return c.image;
}
