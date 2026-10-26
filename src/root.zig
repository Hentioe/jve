const std = @import("std");
const errors = @import("errors.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;

pub const app_env = @import("app_env.zig");
pub const xdg = @import("xdg");
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

const DisplayMode = config.DisplayMode;

const io = std.Io.Threaded.global_single_threaded.io();

// glibc 为每个线程维护独立的 malloc arena。工作线程释放大块内存后，
// 内存会滞留在各自的 arena 中不归还操作系统，导致轮换图片时 RSS 持续上涨。
// 限制 arena 数量即可让这些缓冲被复用（此为 glibc 常量 M_ARENA_MAX）。
const M_ARENA_MAX: c_int = -8;
extern "c" fn mallopt(param: c_int, value: c_int) c_int;

pub const Subsystems = struct {
    pub const Name = enum { app_env, xdg, config, vips, gallery, ui, display, remover };
    pub const NameSet = std.EnumSet(Name);
    pub const InitOpts = struct {
        environ_map: *const Environ.Map,
        config_path: ?[]const u8 = null,
        file_path: ?[]const u8 = null,
    };

    pub const all: NameSet = .full;

    pub fn buildOpts(options: std.process.Init) InitOpts {
        return InitOpts{
            .environ_map = options.environ_map,
        };
    }

    pub fn init(systems: NameSet, allocator: Allocator, opts: InitOpts, trace: *StepTrace) !void {
        // 限制 malloc arena 数量，避免工作线程造成的内存滞留
        if (mallopt(M_ARENA_MAX, 2) == 0) return error.MalloptFailed;

        if (systems.contains(.app_env)) {
            app_env.init(.{ .trace = trace, .environ_map = opts.environ_map });
            try trace.mark("app_env.init");
        }
        if (systems.contains(.xdg)) {
            xdg.init(opts.environ_map);
            try trace.mark("xdg.init");
        }
        if (systems.contains(.config)) {
            config.init(allocator, opts.config_path) catch |err| return showInitDiag(allocator, err);
            try trace.mark("config.init");
        }
        if (systems.contains(.vips)) {
            vips.init(allocator) catch |err| return showInitDiag(allocator, err);
            try trace.mark("vips.init");
        }
        if (systems.contains(.gallery)) {
            gallery.init(allocator, opts.file_path orelse ".") catch |err| return showInitDiag(allocator, err);
            try trace.mark("gallery.init");
        }
        if (systems.contains(.ui)) {
            try ui.init();
            try trace.mark("ui.init");
        }
        if (systems.contains(.display)) {
            try display.init(allocator);
            try trace.mark("display.init");
        }
    }

    pub fn deinit(systems: NameSet) void {
        remover.deinit(); // remover 是按需延迟初始化的，无需在显式初始化
        if (systems.contains(.display)) display.deinit();
        if (systems.contains(.ui)) ui.deinit();
        if (systems.contains(.gallery)) gallery.deinit();
        if (systems.contains(.vips)) vips.deinit();
        if (systems.contains(.config)) config.deinit();
        if (systems.contains(.app_env)) app_env.deinit();
    }
};

pub fn extensions() ![]const []const u8 {
    return try vips.formats.get();
}

pub fn clearCache(allocator: Allocator, config_path: ?[]const u8) !void {
    app_env.init(.{});
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
    const stat = Io.Dir.cwd().statFile(io, file_path, .{}) catch |err| return err;
    // 检查输入是否为文件
    if (stat.kind != .file) return LoadError.NotAFile;
    return try vips.loader.load(allocator, file_path);
}

pub fn show(allocator: Allocator, display_mode: ?[]const u8) !void {
    var mode: DisplayMode = undefined;
    if (display_mode) |s| (if (DisplayMode.parse(s)) |m| {
        mode = m;
    } else {
        std.log.warn("Invalid display mode: \"{s}\", falling back to: \"{f}\"", .{ s, config.get().display_mode });
        mode = config.get().display_mode;
    }) else {
        mode = config.get().display_mode;
    }
    std.log.info("Display mode: {s}", .{@tagName(mode)});
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
    // 必要的初始化
    app_env.init(.{});
    try ui.init();
    try display.init(allocator);
    // 确保错误被记录
    app_env.ensureFatal(err);
    try showDiag(allocator);
    return err; // 返回原错误
}

pub fn showDiag(allocator: Allocator) !void {
    var diag = try display.Diag.init(allocator);
    defer diag.deinit();

    std.debug.assert(try diag.show() == .quit);
}
