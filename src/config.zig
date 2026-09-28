const std = @import("std");
const Allocator = std.mem.Allocator;

pub const paths = @import("config/paths.zig");
pub const loader = @import("config/loader.zig");
pub const errors = @import("config/errors.zig");

pub fn init(allocator: Allocator, config_path: ?[]const u8) errors.Error!void {
    try loader.load(allocator, config_path);
}
