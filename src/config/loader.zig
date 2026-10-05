const std = @import("std");
const toml = @import("toml");
const paths = @import("paths.zig");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;
const Error = errors.Error;

pub const AnimationConfig = struct {
    image_switch: bool, // 是否启用图片切换动画
};

pub const ModelsConfig = struct {
    dir: []const u8, // 模型目录
    birefnet: ?BiRefNet = null, // BiRefNet 模型配置
    magic_touch: ?MagicTouch = null, // MagicTouch 模型配置
};

pub const BiRefNet = struct {
    standard_model: []const u8, // 标准模型文件
    lite_model: []const u8, // 轻量模型文件
    used_variant: []const u8 = "lite", // 使用的变体
};

pub const MagicTouch = struct {
    model: []const u8, // MagicTouch 模型文件
};

pub const MainConfig = struct {
    base_dir: ?[]const u8 = null, // 基础目录（自动设置）
    default_mode: []const u8 = "sdl_gpu", // 默认模式
    min_scale: f32 = 0.5, // 最小缩放倍数
    max_scale: f32 = 3.0, // 最大缩放倍数
    screenshot_dir: ?[]const u8 = null, // 截图保存目录
    shader_dir: ?[]const u8 = null, // 着色器目录
    animation: AnimationConfig = .{
        .image_switch = true,
    },
    models: ModelsConfig = .{
        .dir = "models",
    },
};

// 两种不同来源的配置
pub const FromVariant = union(enum) {
    parsed: toml.Parsed(MainConfig), // 来自解析器
    owned: MainConfig, // 来自默认值构造

    pub inline fn get(self: *const FromVariant) *const MainConfig {
        switch (self.*) {
            .parsed => |*parsed| return &parsed.value,
            .owned => |*owned| return owned,
        }
    }
};

pub const Loaded = struct {
    allocator: Allocator,
    config: FromVariant,

    pub fn get(self: *const Loaded) *const MainConfig {
        return self.config.get();
    }

    pub fn deinit(self: *Loaded) void {
        switch (self.config) {
            .parsed => |*parsed| {
                if (parsed.value.base_dir) |s| self.allocator.free(s);
                parsed.deinit();
            },
            .owned => |*owned| {
                if (owned.base_dir) |s| self.allocator.free(s);
            },
        }
        self.* = undefined;
    }
};

pub fn load(allocator: Allocator, config_path: ?[]const u8) Error!Loaded {
    const path = if (config_path) |path| path else val: {
        break :val try paths.findConfigFile(allocator, "jve", "config.toml");
    };

    defer if (path) |p| {
        if (config_path == null) allocator.free(p);
    };

    // 如果存在配置文件，解析它。否则返回默认配置。
    if (path) |p| {
        std.log.info("Loading config file: {s}", .{p});

        var parser = toml.Parser(MainConfig).init(allocator);
        defer parser.deinit();

        var parsed = parser.parseFile(p) catch |err| {
            std.log.err("Failed to parse config file: {}", .{err});
            return Error.ParseError;
        };
        // 附加基础目录路径
        const base_dir = std.fs.path.dirname(p) orelse ".";
        parsed.value.base_dir = try allocator.dupe(u8, base_dir);

        return Loaded{ .allocator = allocator, .config = .{ .parsed = parsed } };
    } else {
        const default = MainConfig{};
        return Loaded{ .allocator = allocator, .config = .{ .owned = default } };
    }
}
