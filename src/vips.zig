const std = @import("std");
const c = @import("vips/c.zig").c;
const h = @import("vips/helper.zig");
const format = @import("vips/format.zig");
const Error = @import("vips/errors.zig").Error;

pub fn init(allocator: std.mem.Allocator) Error!void {
    // 初始化 vips
    if (!h.check(c.vips_init("imageviewer"))) return Error.VipsInitFailed;
    // 关闭 vips 缓存
    c.vips_cache_set_max(0);
    // 初始化格式缓存
    try format.init(allocator);
}

pub fn deinit() void {
    c.vips_shutdown();
    format.deinit();
}
