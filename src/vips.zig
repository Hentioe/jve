const std = @import("std");
const c = @import("vips/c.zig").c;
const h = @import("vips/helper.zig");

pub const formats = @import("vips/formats.zig");
pub const loader = @import("vips/loader.zig");
pub const writer = @import("vips/writer.zig");
pub const Image = @import("vips/Image.zig");
pub const LImage = loader.LoadedImage;
pub const Error = @import("vips/errors.zig").Error;

pub fn init(allocator: std.mem.Allocator) Error!void {
    // 初始化 vips
    if (!h.check(c.vips_init("jve"))) return Error.VipsInitFailed;
    // 关闭 vips 缓存
    c.vips_cache_set_max(0);
    // 初始化格式缓存
    try formats.init(allocator);
}

pub fn deinit() void {
    c.vips_shutdown();
    formats.deinit();
}
