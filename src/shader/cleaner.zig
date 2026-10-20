const std = @import("std");
const xdg = @import("xdg");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const consts = @import("consts.zig");
const Error = @import("errors.zig").Error;

pub fn deleteCacheDir(allocator: Allocator) Error!bool {
    const home = try xdg.getCacheHome(allocator);
    defer allocator.free(home);
    const dir_path = try std.fs.path.join(allocator, &.{ home, consts.CACHE_APP, consts.CACHE_SUBDIR });
    defer allocator.free(dir_path);
    if (shared.pathExists(dir_path)) {
        try std.fs.cwd().deleteTree(dir_path);
        return true;
    }

    return false;
}
