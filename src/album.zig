const std = @import("std");
const root = @import("root.zig");
const LImage = root.loader.LoadedImage;
const Allocator = std.mem.Allocator;
const Scanner = @import("Scanner.zig");

const AlbumError = error{
    AlbumNoImageSelected,
    AlbumNoImageLeft,
    AlbumCurrentFileNotFound,
};

const PathJoinError = error{PathJoinFailed};

pub const Error = AlbumError || PathJoinError || root.LoadError || Scanner.Error || std.posix.UnlinkError;

// 全局缓存
const Cache = struct {
    allocator: Allocator,
    scanner: Scanner,
    image: LImage,
    dirty: bool,
    full_path: ?[]const u8 = null,

    pub fn deinit(self: *Cache) void {
        self.image.deinit();
        self.scanner.deinit();
        if (self.full_path) |full_path| self.allocator.free(full_path);
        self.* = undefined;
    }

    pub fn freeOldAndupdateFullPath(self: *Cache, path: []const u8) void {
        if (self.full_path) |full_path| self.allocator.free(full_path);
        self.full_path = path;
    }
};
var initialized: bool = false;
var cache: Cache = undefined;

// 扫描文件所在目录，并定位到该文件；文件不在结果中时停在第一个
pub fn init(allocator: Allocator, file_path: []const u8) Error!void {
    const dir = std.fs.path.dirname(file_path) orelse ".";
    const base = std.fs.path.basename(file_path);
    var scanner = try Scanner.init(allocator, dir, try root.extensions());
    errdefer scanner.deinit();
    // 选择当前文件
    if (!scanner.select(base)) return Error.AlbumCurrentFileNotFound;
    // 加载图片
    std.log.info("Loading image: {s}", .{file_path});
    const image = try root.load(allocator, file_path);
    // 输出图像信息
    std.log.info("Current image: {s}", .{base});
    std.log.info("Image shape: {f}", .{image.shape});
    cache = Cache{
        .allocator = allocator,
        .scanner = scanner,
        .image = image,
        .dirty = false,
        // 初始化的路径不要保存，cli 会负责回收
    };
    initialized = true;
}

pub fn deinit() void {
    if (initialized) {
        cache.deinit();
        initialized = false;
    }
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

pub fn current() Error!LImage {
    if (cache.dirty) { // 如果缓存脏了，重新加载当前图片
        std.log.info("cache is dirty, reloading current image", .{});
        try reloadCurrent();
    }
    return cache.image;
}

// 删除当前图片
pub fn deleteCurrentGetNext() Error!LImage {
    if (cache.scanner.current()) |file_name| {
        const dir_path = cache.scanner.dir_path;
        const full_path = std.fs.path.join(cache.allocator, &[_][]const u8{ dir_path, file_name }) catch |err| {
            std.log.err("Failed to join path: {}", .{err});
            return Error.PathJoinFailed;
        };
        defer cache.allocator.free(full_path);
        std.log.info("Deleting current image: {s}", .{full_path});
        try std.fs.cwd().deleteFile(full_path);
        // 重新扫描
        try cache.scanner.rescan();
        if (try next() == null) return Error.AlbumNoImageLeft;
        return try current();
    } else {
        return Error.AlbumNoImageSelected;
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
            return Error.PathJoinFailed;
        };
        // 更新缓存中的路径
        cache.freeOldAndupdateFullPath(full_path);
        // 加载图片
        const image = try root.load(cache.allocator, full_path);
        // 缓存图片
        cache.image = image;
        std.log.info("Current image: {s}", .{image.file_name});
        // 标记缓存为干净
        cache.dirty = false;
    } else {
        // 没有选择图片
        return Error.AlbumNoImageSelected;
    }
}
