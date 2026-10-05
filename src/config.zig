const std = @import("std");
const Allocator = std.mem.Allocator;

pub const paths = @import("config/paths.zig");
pub const loader = @import("config/loader.zig");
pub const Error = @import("config/errors.zig").Error;
pub const Sort = loader.Sort;

var initialized: bool = false;
var cache: loader.Loaded = undefined;

pub fn init(allocator: Allocator, config_path: ?[]const u8) Error!void {
    cache = try loader.load(allocator, config_path);
    initialized = true;
}

pub fn deinit() void {
    if (!initialized) return;
    cache.deinit();
    cache = undefined;
    initialized = false;
}

pub inline fn get() *const loader.MainConfig {
    return cache.get();
}

/// 已解析且保证有效的 Mod 键，外部无需再做错误或空值处理
pub inline fn modKey() loader.ModKey {
    return cache.mod_key;
}

/// 已解析且保证有效的排序方式，外部无需再做错误或空值处理
pub inline fn sort() loader.Sort {
    return cache.sort;
}

/// 基于配置主目录和相对路径，创建完整路径
pub fn allocFullPath(allocator: Allocator, relative_path: []const u8) Error![]const u8 {
    if (get().base_dir) |base_dir| {
        return try std.fs.path.join(allocator, &.{ base_dir, relative_path });
    } else {
        return Error.ConfigNotFound;
    }
}
