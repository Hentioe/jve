const std = @import("std");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;

pub const config = @import("config");
pub const vips = @import("vips");
pub const display = @import("display.zig");
pub const gallery = @import("gallery.zig");
pub const clipboard = @import("clipboard.zig");
pub const remover = @import("ai").remover;
pub const State = display.State;
pub const LoadError = errors.LoadError;

const DisplayMode = display.Viewer.Mode;

// glibc 为每个线程维护独立的 malloc arena。工作线程释放大块内存后，
// 内存会滞留在各自的 arena 中不归还操作系统，导致轮换图片时 RSS 持续上涨。
// 限制 arena 数量即可让这些缓冲被复用（此为 glibc 常量 M_ARENA_MAX）。
const M_ARENA_MAX: c_int = -8;
extern "c" fn mallopt(param: c_int, value: c_int) c_int;

pub fn init(allocator: std.mem.Allocator, file_path: []const u8, config_path: ?[]const u8) !void {
    // 限制 malloc arena 数量，避免工作线程造成的内存滞留
    if (mallopt(M_ARENA_MAX, 2) == 0) return error.MalloptFailed;
    try config.init(allocator, config_path); // todo: 支持手动传递配置
    try vips.init(allocator);
    try gallery.init(allocator, file_path);
    try display.init();
}

pub fn deinit() void {
    // 和 init 的顺序相反，先 deinit 后初始化的组件
    remover.deinit(); // remover 是按需延迟初始化的，无需在此处初始化
    display.deinit();
    gallery.deinit();
    vips.deinit();
    config.deinit();
}

pub fn vips_init(allocator: Allocator) !void {
    try vips.init(allocator);
}

pub fn vips_deinit() void {
    vips.deinit();
}

pub fn display_init() !void {
    try display.init();
}

pub fn display_deinit() void {
    display.deinit();
}

pub fn isSupported(suffix: []const u8) !bool {
    return try vips.formats.isSupported(suffix);
}

pub fn extensions() ![]const []const u8 {
    return try vips.formats.get();
}

pub fn load(allocator: Allocator, file_path: []const u8) LoadError!vips.LImage {
    // 检查文件的可访问性
    const stat = std.fs.cwd().statFile(file_path) catch |err| return err;
    // 检查输入是否为文件
    if (stat.kind != .file) return LoadError.NotAFile;
    return try vips.loader.load(allocator, file_path);
}

pub fn show(allocator: Allocator, display_mode: []const u8) !void {
    std.log.info("Display mode: {s}", .{display_mode});
    const mode: DisplayMode = if (std.mem.eql(u8, display_mode, "preview"))
        .preview
    else if (std.mem.eql(u8, display_mode, "gpu"))
        .gpu
    else {
        std.log.err("Unknown display mode: {s}", .{display_mode});
        return error.UnknownDisplayMode;
    };

    try display.show(mode, allocator);
}

pub fn showWelcome(allocator: Allocator) !void {
    var welcome = try display.Welcome.init(allocator);
    defer welcome.deinit();

    std.debug.assert(try welcome.show() == .quit);
}
