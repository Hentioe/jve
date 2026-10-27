const std = @import("std");
const sdl = @import("sdl");
const slang = @import("slang");
const config = @import("../config.zig");
const app_env = @import("../app_env.zig");
const consts = @import("consts.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const loader = @import("loader.zig");
const loaded = @import("loaded.zig");
const Cache = @import("Cache.zig");
const Scanner = @import("../Scanner.zig");
const Device = @import("../Device.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

const io = std.Io.Threaded.global_single_threaded.io();

/// 内建背景着色器的名字和 @embedFile 的映射
pub const BUILTIN_BG_SHADERS = std.StaticStringMap([]const u8).initComptime(.{
    .{ "black", @embedFile("black_bg.frag.spv") },
    .{ "classic", @embedFile("checker_bg.frag.spv") },
    .{ "rainbow", @embedFile("rainbow_bg.frag.spv") },
    .{ "tiles", @embedFile("tiles_bg.frag.spv") },
});

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

pub fn loadAll(allocator: Allocator, gpu: *const sdl.Gpu, shader_dir: []const u8) Error!loaded.All {
    var self = try Self.init(allocator, shader_dir);
    defer self.deinit();
    var cache = try Cache.init(allocator, slang.DEFAULT_PROFILE);
    defer cache.deinit();
    defer if (slang.isInitialized()) slang.deinit();
    try loadBackground(self.allocator, gpu, &cache, self.scanner.dir_path);
    return try self.compileShaders(self.allocator, gpu, &cache);
}

pub fn compileShaders(self: *Self, allocator: Allocator, gpu: *const sdl.Gpu, cache: *Cache) Error!loaded.All {
    const base_dir = self.scanner.dir_path;
    const files = self.scanner.items();

    var loaded_all: loaded.All = try .init(allocator);
    if (files.len == 0) return loaded_all;

    errdefer {
        for (loaded_all.list.items) |item| gpu.releaseGPUShader(item.shader);
        loaded_all.deinit();
    }

    for (files) |file| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, file });
        defer allocator.free(full_path);
        // 否则作为普通着色器添加进列表
        const bytes = try resolveSpirv(allocator, cache, file, full_path);
        defer allocator.free(bytes);

        const shader = loader.load(gpu, bytes, "main", .fragment, .{ .samplers = 1, .buffers = 0 }) catch |err| {
            return app_env.report(err, @src(), "着色器 `{s}` 加载失败", .{file});
        };

        const key = std.fs.path.stem(file);
        if (config.get().shaders.custom) |c| (if (c.get(key)) |s| {
            try loaded_all.add(.{
                .activation = .manual,
                .keybinding = s.keybinding,
                .shader = shader,
            });
            continue;
        } else {
            // 配置中的自定义着色器不存在
            std.log.warn("Configured custom shader not found: {s}", .{file});
        });

        // 作为默认着色器
        try loaded_all.add(.{ .activation = .default, .shader = shader });
    }

    try cache.save();
    return loaded_all;
}

/// 加载背景着色器，仅允许调用一次
pub fn loadBackground(allocator: Allocator, gpu: *const sdl.Gpu, cache: *Cache, shader_dir: []const u8) Error!void {
    std.debug.assert(Device.getBackgroundShader() == null);
    if (config.get().shaders.background) |name| {
        // 先从内建背景着色器中查找
        if (BUILTIN_BG_SHADERS.get(name)) |shader_data| {
            std.log.info("Loading built-in background shader: {s}", .{name});
            const shader = try loader.load(gpu, shader_data, "main", .fragment, .{ .samplers = 0, .buffers = 0 });
            Device.setBackgroundShader(shader);
            return;
        }
        // 再尝试加载文件，走与用户着色器一致的缓存
        const cache_name = try std.fs.path.join(allocator, &.{ consts.BACKGROUND_DIR, name });
        defer allocator.free(cache_name);
        const full_path = try std.fs.path.join(allocator, &.{ shader_dir, consts.BACKGROUND_DIR, name });
        defer allocator.free(full_path);
        std.log.info("Loading background shader from file: {s}", .{full_path});

        const bytes = try resolveSpirv(allocator, cache, cache_name, full_path);
        defer allocator.free(bytes);
        try cache.save();

        const shader = loader.load(gpu, bytes, "main", .fragment, .{ .samplers = 0, .buffers = 0 }) catch |err| {
            return app_env.report(err, @src(), "背景着色器 `{s}` 加载失败", .{name});
        };
        Device.setBackgroundShader(shader);
    }
}

/// 获取某个着色器的 SPIR-V：优先命中缓存，未命中则编译并写回。
/// 返回的字节由调用方释放。
fn resolveSpirv(allocator: Allocator, cache: *Cache, name: []const u8, full_path: []const u8) Error![]u8 {
    const stat = Io.Dir.cwd().statFile(io, full_path, .{}) catch |err| {
        return app_env.report(err, @src(), "着色器 `{s}` 读取失败：{s}", .{ name, @errorName(err) });
    };
    const mtime = stat.mtime.nanoseconds;
    const size: u64 = @intCast(stat.size);

    // mtime 与 size 都一致：视作未变，直接读缓存
    if (cache.get(name)) |entry| if (entry.mtime == mtime and entry.size == size) {
        if (try cache.readSpv(allocator, name)) |bytes| {
            std.log.info("Shader from cache: {s}", .{name});
            return bytes;
        }
    };

    // 读取源码并计算内容哈希
    const source = std.Io.Dir.cwd().readFileAllocOptions(
        io,
        full_path,
        allocator,
        .unlimited,
        .of(u8),
        0,
    ) catch return Error.ShaderReadFailed;
    defer allocator.free(source);
    const hash = std.hash.Wyhash.hash(0, source);

    // 元数据变了但哈希一致：内容未变，仅刷新摘要
    if (cache.get(name)) |entry| if (entry.hash == hash) {
        cache.touch(name, mtime, size);
        if (try cache.readSpv(allocator, name)) |bytes| {
            std.log.info("Shader from cache: {s}", .{name});
            return bytes;
        }
    };

    // 重新编译着色器
    try slang.init(name); // 由外部 deinit
    var compiled = try slang.compileToSpirv(full_path, source, .{ .entry = "main" });
    defer compiled.deinit();

    const bytes = try allocator.dupe(u8, compiled.bytes());
    errdefer allocator.free(bytes);
    try cache.write(allocator, name, bytes, mtime, size, hash);
    std.log.info("Shader recompiled: {s}", .{name});
    return bytes;
}
