const std = @import("std");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;

pub const app_env = @import("app_env.zig");
pub const config = @import("config.zig");
pub const vips = @import("vips");
pub const slang = @import("slang");
pub const display = @import("display.zig");
pub const gallery = @import("gallery.zig");
pub const shader = @import("shader.zig");
pub const clipboard = @import("clipboard.zig");
pub const ui = @import("ui.zig");
pub const remover = @import("ai.zig").remover;
pub const LoadError = errors.LoadError;
pub const StepTrace = @import("StepTrace.zig");

const DisplayMode = display.Viewer.Mode;

// glibc 为每个线程维护独立的 malloc arena。工作线程释放大块内存后，
// 内存会滞留在各自的 arena 中不归还操作系统，导致轮换图片时 RSS 持续上涨。
// 限制 arena 数量即可让这些缓冲被复用（此为 glibc 常量 M_ARENA_MAX）。
const M_ARENA_MAX: c_int = -8;
extern "c" fn mallopt(param: c_int, value: c_int) c_int;

pub fn init(allocator: std.mem.Allocator, trace: *StepTrace, file_path: []const u8, config_path: ?[]const u8) !void {
    // 限制 malloc arena 数量，避免工作线程造成的内存滞留
    if (mallopt(M_ARENA_MAX, 2) == 0) return error.MalloptFailed;
    app_env.init(trace);
    try trace.mark("app_env.init");
    config.init(allocator, config_path) catch |err| return showInitDiag(allocator, err);
    try trace.mark("config.init");
    vips.init(allocator) catch |err| return showInitDiag(allocator, err);
    try trace.mark("vips.init");
    gallery.init(allocator, file_path) catch |err| return showInitDiag(allocator, err);
    try trace.mark("gallery.init");
    try ui.init();
    try trace.mark("ui.init");
    try display.init(allocator);
    try trace.mark("display.init");
}

pub fn deinit() void {
    // 和 init 的顺序相反，先 deinit 后初始化的组件
    remover.deinit(); // remover 是按需延迟初始化的，无需在此处初始化
    display.deinit();
    ui.deinit();
    gallery.deinit();
    vips.deinit();
    config.deinit();
    app_env.deinit();
}

pub fn vips_init(allocator: Allocator) !void {
    try vips.init(allocator);
}

pub fn vips_deinit() void {
    vips.deinit();
}

pub fn display_init(allocator: Allocator) !void {
    app_env.init(null);
    try ui.init();
    try display.init(allocator);
}

pub fn display_deinit() void {
    display.deinit();
    ui.deinit();
    app_env.deinit();
}

pub fn extensions() ![]const []const u8 {
    return try vips.formats.get();
}

pub fn clearCache(allocator: Allocator, config_path: ?[]const u8) !void {
    app_env.init(null);
    defer app_env.deinit();
    try config.init(allocator, config_path);
    defer config.deinit();
    const r = try shader.cleaner.deleteInvalidCache(allocator);
    if (r.deleted_dir) {
        std.log.info("Deleted shader cache directory", .{});
        return;
    }
    if (r.deleted_count > 0) {
        std.log.info("Deleted {d} invalid cache file(s)", .{r.deleted_count});
    }
    if (r.deleted_entries > 0) {
        std.log.info("Deleted {d} invalid cache entries", .{r.deleted_entries});
    }
    if (r.deleted_count == 0 and r.deleted_entries == 0) {
        std.log.info("No invalid cache files and entries found", .{});
    }
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

    display.show(allocator, mode) catch |err| {
        app_env.ensureFatal(err);
        try showDiag(allocator);
    };
}

pub fn showWelcome(allocator: Allocator) !void {
    var welcome = try display.Welcome.init(allocator);
    defer welcome.deinit();

    std.debug.assert(try welcome.show() == .quit);
}

pub fn showInitDiag(allocator: Allocator, err: anyerror) !void {
    try display_init(allocator); // 仅做显示初始化
    app_env.ensureFatal(err);
    try showDiag(allocator);
    return err;
}

pub fn showDiag(allocator: Allocator) !void {
    var diag = try display.Diag.init(allocator);
    defer diag.deinit();

    std.debug.assert(try diag.show() == .quit);
}
