const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const consts = @import("consts.zig");
const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;

const Cache = struct {
    const Self = @This();

    allocator: Allocator,
    suffixes: [][]const u8,

    pub fn deinit(self: *Self) void {
        for (self.suffixes[0..self.suffixes.len]) |s| self.allocator.free(s);
        self.allocator.free(self.suffixes);
    }
};
var cache: ?Cache = null;

pub fn init(allocator: Allocator) Error!void {
    if (cache == null) {
        // 获取 Vips 支持的文件后缀列表
        const suffixes_raw: [*c][*c]u8 = c.vips_foreign_get_suffixes();
        if (suffixes_raw == null) return Error.VipsSuffixesGetFailed;
        defer c.g_strfreev(suffixes_raw);
        // 数元素个数（遇到 null 为止）
        var n: usize = 0;
        while (suffixes_raw[n] != null) : (n += 1) {}
        // 申请内存
        const suffixes = try allocator.alloc([]const u8, n);
        // 逐个复制
        var i: usize = 0;
        while (i < n) : (i += 1) {
            suffixes[i] = try allocator.dupe(u8, std.mem.span(suffixes_raw[i]));
        }
        // 输出支持的格式数量
        std.log.info("Vips supports {d} format(s)", .{n});
        // 构造缓存
        cache = Cache{ .allocator = allocator, .suffixes = suffixes };
    }
}

pub fn deinit() void {
    if (cache) |*ref| {
        ref.deinit();
        cache = null;
    }
}

pub fn isSupported(suffix: []const u8) Error!bool {
    if (cache == null) return Error.VipsNotInitialized;
    for (cache.?.suffixes) |s| {
        if (std.mem.eql(u8, s, suffix)) return true;
    }
    return false;
}
