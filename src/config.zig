const std = @import("std");
const Allocator = std.mem.Allocator;

pub const paths = @import("config/paths.zig");
pub const loader = @import("config/loader.zig");
pub const errors = @import("config/errors.zig");

var initialized: bool = false;
var cache: loader.Loaded = undefined;

pub fn init(allocator: Allocator, config_path: ?[]const u8) errors.Error!void {
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
