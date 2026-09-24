const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const format = @import("format.zig");
const Error = @import("errors.zig").Error;

pub fn initialize(allocator: std.mem.Allocator) Error!void {
    // 初始化 vips
    if (c.vips_init("imageviewer") != 0) {
        h.printError();
        return Error.VipsInitFailed;
    }
    // 关闭 vips 缓存
    c.vips_cache_set_max(0);
    // 初始化格式模块（包含缓存）
    try format.init(allocator);
}

pub fn shutdown() void {
    c.vips_shutdown(); // todo: 解决调用产生的 glib 错误日志
    format.deinit();
}
