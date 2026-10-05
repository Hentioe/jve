const std = @import("std");
const c = @import("c.zig").c;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Error = @import("errors.zig").Error;

const Cache = struct {
    arena: ArenaAllocator,
    suffixes: [][]const u8,

    pub fn init(gpa: Allocator, ptr: [*c][*c]u8, len: usize) Error!Cache {
        // 创建 ArenaAllocator
        var arena: std.heap.ArenaAllocator = .init(gpa);
        errdefer arena.deinit(); // 避免后续错误导致内存不释放
        // 申请内存
        const suffixes = try arena.allocator().alloc([]const u8, len);
        // 逐个复制
        var i: usize = 0;
        while (i < len) : (i += 1) {
            suffixes[i] = try arena.allocator().dupe(u8, std.mem.span(ptr[i]));
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
    return cache.suffixes;
}

pub fn init(allocator: Allocator) Error!void {
    // 获取 Vips 支持的文件后缀列表
    const suffixes_ptr = c.vips_foreign_get_suffixes() orelse return Error.VipsForeignGetSuffixesFailed;
    defer c.g_strfreev(suffixes_ptr);
    // 数元素个数（遇到 null 为止）
    var n: usize = 0;
    while (suffixes_ptr[n] != null) : (n += 1) {}
    // 输出支持的格式数量
    std.log.info("Vips supports {d} format(s)", .{n});
    // 初始化缓存
    cache = try Cache.init(allocator, suffixes_ptr, n);
    initialized = true;
}

pub fn deinit() void {
    if (!initialized) return;
    cache.deinit();
    cache = undefined;
    initialized = false;
}

pub fn isSupported(suffix: []const u8) Error!bool {
    for (cache.suffixes) |s| {
        if (std.mem.eql(u8, s, suffix)) return true;
    }
    return false;
}
