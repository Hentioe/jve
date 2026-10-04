const std = @import("std");
const c = @import("vips/c.zig").c;
const h = @import("vips/helper.zig");

pub const formats = @import("vips/formats.zig");
pub const Image = @import("vips/Image.zig");
pub const Error = @import("vips/errors.zig").Error;

// glibc 为每个线程维护独立的 malloc arena。libvips 的工作线程释放大图缓冲后，
// 内存会滞留在各自的 arena 中不归还操作系统，导致轮换图片时 RSS 持续上涨。
// 限制 arena 数量即可让这些缓冲被复用（此为 glibc 常量 M_ARENA_MAX）。
const M_ARENA_MAX: c_int = -8;
extern "c" fn mallopt(param: c_int, value: c_int) c_int;

pub fn init(allocator: std.mem.Allocator) Error!void {
    // 初始化 vips
    if (!h.check(c.vips_init("imageviewer"))) return Error.VipsInitFailed;
    // 限制 malloc arena 数量，避免 libvips 工作线程造成的内存滞留
    if (mallopt(M_ARENA_MAX, 2) == 0) return Error.MalloptFailed;
    // 关闭 vips 缓存
    c.vips_cache_set_max(0);
    // 初始化格式缓存
    try formats.init(allocator);
}

pub fn deinit() void {
    c.vips_shutdown();
    formats.deinit();
}
