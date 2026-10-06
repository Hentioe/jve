const std = @import("std");
const c = @import("c.zig").c;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Suffixes = std.StringArrayHashMap(void);
const Error = @import("errors.zig").Error;

// vips 格式黑名单
const FORMAT_BLACKLIST = &[_][]const u8{
    ".csv", ".dz", ".szi", ".mat", ".v", ".vips", ".raw", // 非图像
    ".fits", ".fit", ".fts", // 天文数据格式
};

const Cache = struct {
    arena: ArenaAllocator,
    suffixes: Suffixes,

    pub fn init(gpa: Allocator, suffixes_ptr: [*c][*c]u8, len: usize) Error!Cache {
        // 用 Arena 分配器管理 suffixes 内存
        var arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena.deinit(); // 避免后续错误导致内存不释放
        // 申请内存
        var suffixes: Suffixes = .init(arena.allocator());
        // 逐个复制
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const s = try arena.allocator().dupe(u8, std.mem.span(suffixes_ptr[i]));
            if (isBlacklisted(s)) { // 跳过黑名单中的格式
                arena.allocator().free(s);
                continue;
            }
            try suffixes.put(s, {});
        }

        return Cache{ .arena = arena, .suffixes = suffixes };
    }

    pub fn deinit(self: *Cache) void {
        self.arena.deinit();
        self.* = undefined;
    }
};
var initialized: bool = false;
var cache: Cache = undefined;

pub fn get() Error![]const []const u8 {
    if (!initialized) return Error.NotInitialized;
    return cache.suffixes.keys();
}

pub fn init(allocator: Allocator) Error!void {
    // 获取 Vips 支持的文件后缀列表
    const suffixes_ptr = c.vips_foreign_get_suffixes() orelse return Error.VipsForeignGetSuffixesFailed;
    defer c.g_strfreev(suffixes_ptr);
    // 数元素个数（遇到 null 为止）
    var n: usize = 0;
    while (suffixes_ptr[n] != null) : (n += 1) {}
    // 初始化缓存
    cache = try Cache.init(allocator, suffixes_ptr, n);
    initialized = true;
    // 输出支持的格式数量
    std.log.info("VIPS library supports {d} format(s)", .{cache.suffixes.keys().len});
}

pub fn deinit() void {
    if (!initialized) return;
    cache.deinit();
    cache = undefined;
    initialized = false;
}

pub fn isSupported(suffix: []const u8) Error!bool {
    return cache.suffixes.contains(suffix);
}

/// 是否在格式黑名单中
pub fn isBlacklisted(suffix: []const u8) bool {
    for (FORMAT_BLACKLIST) |format| {
        if (std.mem.eql(u8, format, suffix)) return true;
    }
    return false;
}
