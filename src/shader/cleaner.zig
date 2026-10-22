const std = @import("std");
const xdg = @import("xdg");
const shared = @import("shared");
const slang = @import("slang");
const consts = @import("consts.zig");
const Allocator = std.mem.Allocator;
const config = @import("../config.zig");
const Cache = @import("Cache.zig");
const Scanner = @import("../Scanner.zig");
const Error = @import("errors.zig").Error;

/// 删除无效缓存：
///   - 缓存清单中不存在对应 `.slang` 文件的条目，会被移除。
///   - 缓存目录中不存在对应清单条目的 `.spv` 文件，会被删除。
pub fn deleteInvalidCache(allocator: Allocator) Error!u32 {
    // 用 arena 简化内存释放
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 获取缓存目录路径
    const home = try xdg.getCacheHome(a);
    const dir_path = try std.fs.path.join(a, &.{ home, consts.CACHE_APP, consts.CACHE_SUBDIR });
    if (!shared.pathExists(dir_path)) { // 目录不存在，直接返回
        std.log.debug("Cache directory does not exist: {s}", .{dir_path});
        return 0;
    }

    var cache = try Cache.init(a, slang.DEFAULT_PROFILE);
    defer cache.deinit();

    var local_keys: std.StringHashMapUnmanaged(void) = .empty;
    defer local_keys.deinit(a);
    // 扫描当前的用户着色器目录
    const shaders_path = try config.allocFullPath(a, config.get().shaders.dir);
    std.log.debug("Shader directory path: {s}", .{shaders_path});
    var shader_scanner = try Scanner.init(a, shaders_path, &.{".slang"}, .{});
    defer shader_scanner.deinit();
    for (shader_scanner.names.items) |name| {
        try local_keys.put(a, name, {});
        std.log.debug("Added shader file to local keys: {s}", .{name});
    }
    // 扫描当前的背景着色器目录
    const background_path = try std.fs.path.join(a, &.{ config.get().shaders.dir, "background" });
    const background_full_path = try config.allocFullPath(a, background_path);
    std.log.debug("Background shader directory path: {s}", .{background_full_path});
    var background_scanner = try Scanner.init(a, background_full_path, &.{".slang"}, .{});
    defer background_scanner.deinit();
    for (background_scanner.names.items) |name| {
        const key = try std.fs.path.join(a, &.{ "background", name }); // 背景着色器条目 key 是目录+文件名组成的路径
        try local_keys.put(a, key, {});
        std.log.debug("Added background shader file to local keys: {s}", .{key});
    }

    // 清理不在本地着色器目录中的缓存条目
    const entries_count = cache.entries.count();
    var i: usize = entries_count;
    while (i > 0) {
        i -= 1; // 每轮都满足 i < 当前 count
        const key = cache.entries.keys()[i]; // 每轮重新取 keys()
        if (local_keys.get(key) == null) {
            cache.entries.orderedRemoveAt(i);
            std.log.debug("Removed cache entry not in local shader directory: {s}", .{key});
        }
    }
    if (entries_count != cache.entries.count()) cache.dirty = true; // 标记缓存为脏，因为有条目被移除
    try cache.save(); // 持久化到硬盘

    // 清理缓存目录中不在条目列表中的文件
    var entry_files = try std.ArrayList([]u8).initCapacity(a, cache.entries.count());
    defer entry_files.deinit(a);
    for (cache.entries.values()) |entry| {
        const file_name = try std.fmt.allocPrint(a, "{d}.spv", .{entry.hash});
        try entry_files.append(a, file_name);
        std.log.debug("Added shader file to entry files: {s}", .{file_name});
    }
    // 扫描缓存目录中的所有 .spv 文件
    var scanner = try Scanner.init(a, dir_path, &.{".spv"}, .{});
    defer scanner.deinit();

    var deleted_count: u32 = 0;
    for (scanner.names.items) |name| {
        var found = false;
        for (entry_files.items) |file| if (std.mem.eql(u8, file, name)) {
            found = true;
            break;
        };
        if (!found) {
            const file_path = try std.fs.path.join(a, &.{ dir_path, name });
            try std.fs.cwd().deleteFile(file_path);
            std.log.info("Deleted shader file not in cache: {s}", .{name});
            deleted_count += 1;
        }
    }
    return deleted_count;
}
