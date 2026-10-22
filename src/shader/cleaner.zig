const std = @import("std");
const xdg = @import("xdg");
const shared = @import("shared");
const slang = @import("slang");
const consts = @import("consts.zig");
const Allocator = std.mem.Allocator;
const Cache = @import("Cache.zig");
const Scanner = @import("../Scanner.zig");
const Error = @import("errors.zig").Error;

/// 删除无效缓存文件：
///   - 不在缓存清单中的 `.spv` 文件
pub fn deleteInvalidCache(allocator: Allocator) Error!u32 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const home = try xdg.getCacheHome(a);
    const dir_path = try std.fs.path.join(a, &.{ home, consts.CACHE_APP, consts.CACHE_SUBDIR });
    if (!shared.pathExists(dir_path)) { // 目录不存在，直接返回
        std.log.debug("Cache directory does not exist: {s}", .{dir_path});
        return 0;
    }

    var cache = try Cache.init(allocator, slang.DEFAULT_PROFILE);
    defer cache.deinit();

    var entry_files = try std.ArrayList([]u8).initCapacity(allocator, cache.entries.count());
    defer entry_files.deinit(allocator);
    var it = cache.entries.iterator();
    while (it.next()) |kv| {
        const file_name = try std.fmt.allocPrint(a, "{d}.spv", .{kv.value_ptr.hash});
        std.log.debug("Adding shader file to entry list: {s}", .{file_name});
        try entry_files.append(a, file_name);
    }
    // 扫描缓存目录中的所有 .spv 文件
    var scanner = try Scanner.init(allocator, dir_path, &.{".spv"}, .{});
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
