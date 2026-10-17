const std = @import("std");
const sdl = @import("sdl");
const config = @import("config");
const errors = @import("errors.zig");
const app_env = @import("../app_env.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const loader = @import("loader.zig");
const Scanner = @import("../Scanner.zig");
const Device = @import("../Device.zig");
const Error = errors.Error;
const Self = @This();

allocator: Allocator,
scanner: Scanner,

pub fn init(allocator: Allocator, sharder_dir: []const u8) Error!Self {
    const scanner = try Scanner.init(allocator, sharder_dir, &[_][]const u8{".slang"}, .{});

    return Self{ .allocator = allocator, .scanner = scanner };
}

pub fn deinit(self: *Self) void {
    self.scanner.deinit();
    self.* = undefined;
}

pub fn scan(self: *Self) Error!void {
    try self.scanner.scan();
}

pub fn compileShaders(self: *Self, allocator: Allocator, gpu: *const sdl.Gpu) Error!ArrayList(*sdl.c.SDL_GPUShader) {
    const base_dir = self.scanner.dir_path;
    const files = self.scanner.items();
    var shaders = try ArrayList(*sdl.c.SDL_GPUShader).initCapacity(allocator, 0);
    for (files) |file| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, file });
        defer allocator.free(full_path);
        // 如果着色器文件名和背景着色器配置名相同，直接跳过。
        if (config.get().shaders.background) |name| if (std.mem.eql(u8, file, name)) continue;
        // 否则作为普通着色器添加进列表。
        std.log.info("Loading user shader: {s}", .{file});
        const sharder = try loader.loadSlangFile(allocator, gpu, full_path, "main", .fragment, .{ .samplers = 1, .buffers = 0 });
        try shaders.append(allocator, sharder);
    }
    return shaders;
}

/// 内建背景着色器的名字和 @embedFile 的映射
pub const BUILTIN_BG_SHADERS = std.StaticStringMap([]const u8).initComptime(.{
    .{ "classic", @embedFile("checker_bg.frag.spv") },
    .{ "rainbow", @embedFile("rainbow_bg.frag.spv") },
});

/// 加载背景着色器，仅允许调用一次
pub fn loadBackground(allocator: Allocator, gpu: *const sdl.Gpu) Error!void {
    std.debug.assert(Device.getBackgroundShader() == null);
    if (config.get().shaders.background) |name| {
        // 先从内建背景着色器中查找
        if (BUILTIN_BG_SHADERS.get(name)) |shader_data| {
            std.log.info("Loading built-in background shader: {s}", .{name});
            const shader = try loader.load(gpu, shader_data, "main", .fragment, .{ .samplers = 0, .buffers = 0 });
            Device.setBackgroundShader(shader);
            return;
        }
        // 再尝试加载文件
        const full_path = try config.allocFullPath(allocator, name);
        defer allocator.free(full_path);
        const sharder = loader.loadSlangFile(allocator, gpu, full_path, "main", .fragment, .{ .samplers = 0, .buffers = 0 }) catch |err| {
            return app_env.report(err, @src(), "背景着色器 `{s}` 加载失败", .{name});
        };
        Device.setBackgroundShader(sharder);
    }
}
