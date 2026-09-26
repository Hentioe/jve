const std = @import("std");
const root = @import("root.zig");
const loader = root.loader;
const Image = loader.Image;
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");

const AlbumError = error{
    CacheNotInitialized,
    NoImageSelected,
    NoImageLeft,
    InvalidPath,
    ImageLoadFailed,
};

pub const Error = AlbumError || root.vips.Error || Scanner.Error || std.posix.UnlinkError;

// 全局缓存
const Cache = struct {
    allocator: Allocator,
    scanner: Scanner,
    image: Image,
    dirty: bool,
    full_path: ?[]const u8 = null,

    pub fn deinit(self: *Cache) void {
        self.image.deinit();
        self.scanner.deinit();
        if (self.full_path) |full_path| self.allocator.free(full_path);
        self.* = undefined;
    }

    pub fn updateFullPath(self: *Cache, path: []const u8) void {
        if (self.full_path) |full_path| self.allocator.free(full_path);
        self.full_path = path;
    }
};
var cache: Cache = undefined;

// 扫描文件所在目录，并定位到该文件；文件不在结果中时停在第一个
pub fn init(allocator: Allocator, file_path: []const u8) !void {
    const dir = std.fs.path.dirname(file_path) orelse ".";
    const base = std.fs.path.basename(file_path);
    var scanner = try Scanner.init(allocator, dir, try root.extensions());
    // 选择当前文件
    _ = scanner.select(base);
    // 加载图片
    const image = try loader.load(allocator, file_path);
    // 输出图像信息
    std.log.info("Current image: {s}", .{base});
    std.log.info("Image size: {d}x{d}", .{ image.width, image.height });
    cache = Cache{
        .allocator = allocator,
        .scanner = scanner,
        .image = image,
        .dirty = false,
        // 初始化的路径不要保存，cli 会负责回收
    };
}

pub fn deinit() void {
    cache.deinit();
    cache = undefined;
}

pub fn next() Error!?[]const u8 {
    std.log.info("Going to next image", .{});
    cache.dirty = true;
    return cache.scanner.next();
}

pub fn prev() Error!?[]const u8 {
    std.log.info("Going to previous image", .{});
    cache.dirty = true;
    return cache.scanner.prev();
}

pub fn current() Error!Image {
    if (cache.dirty) { // 如果缓存脏了，重新加载当前图片
        std.log.info("Cache is dirty, reloading current image", .{});
        try reloadCurrent();
    }
    return cache.image;
}

// 删除当前图片
pub fn deleteCurrentGetNext() Error!Image {
    if (cache.scanner.current()) |file_name| {
        const dir_path = cache.scanner.dir_path;
        const full_path = std.fs.path.join(cache.allocator, &[_][]const u8{ dir_path, file_name }) catch |err| {
            std.log.err("Failed to join path: {}", .{err});
            return Error.InvalidPath;
        };
        defer cache.allocator.free(full_path);
        std.log.info("Deleting current image: {s}", .{full_path});
        try std.fs.cwd().deleteFile(full_path);
        // 重新扫描
        try cache.scanner.rescan();
        if (try next() == null) return Error.NoImageLeft;
        return try current();
    } else {
        return Error.NoImageSelected;
    }
}

fn reloadCurrent() Error!void {
    std.log.info("Reloading current image", .{});
    if (cache.scanner.current()) |file_name| {
        // 如果有图片，释放它
        cache.image.deinit();
        // 组合成文件路径
        const dir_path = cache.scanner.dir_path;
        const full_path = std.fs.path.join(cache.allocator, &[_][]const u8{ dir_path, file_name }) catch |err| {
            std.log.err("Failed to join path: {}", .{err});
            return Error.InvalidPath;
        };
        // 更新缓存中的路径（后续释放需要）
        cache.updateFullPath(full_path);
        // 加载图片
        const image = try loader.load(cache.allocator, full_path);
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
