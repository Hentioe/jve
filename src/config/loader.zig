const std = @import("std");
const toml = @import("toml");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const app_env = @import("../app_env.zig");
const paths = @import("paths.zig");
const Error = @import("errors.zig").Error;

pub const Screenshot = struct {
    dir: ?[]const u8 = null, // 截图保存目录
    format: []const u8, // 截图的输出格式
};

pub const Titlebar = struct {
    custom: bool, // 是否启用自定义标题栏
    opacity: ?f32, // 标题栏透明度
    no_title_text: ?bool, // 是否不显示标题文字
    no_file_size: ?bool, // 是否不显示图片尺寸
    no_app_name: ?bool, // 是否不显示应用后缀
};

pub const AnimationConfig = struct {
    image_switch: bool, // 是否启用图片切换动画
};

pub const ShadersConfig = struct {
    dir: []const u8, // 着色器目录
    background: ?[]const u8 = null, // 背景着色器
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
    disable_memory_optimization: bool = false, // 是否禁用内存优化
};

pub const MagicTouch = struct {
    model: []const u8, // MagicTouch 模型文件
};

// 可配置的 Mod 键白名单
const MOD_KEYS = [_]sdl.Key{
    .left_alt,
    .right_alt,
    .left_ctrl,
    .right_ctrl,
    .left_shift,
    .right_shift,
    .left_gui,
    .right_gui,
};
const default_mod_key: sdl.Key = .left_alt;

// 可配置的文件排序方式（与配置字符串一一对应）
pub const Sort = enum {
    name,
    created_desc,
    created_asc,
    modified_desc,
    modified_asc,

    pub const default: Sort = .name;

    // 将配置字符串映射为排序方式，无法识别时返回 null
    pub fn parse(name: []const u8) ?Sort {
        return std.meta.stringToEnum(Sort, name);
    }
};

pub const MainConfig = struct {
    base_dir: ?[]const u8 = null, // 基础目录（自动设置）
    display_mode: []const u8 = "gpu", // 默认模式
    min_scale: f32 = 0.5, // 最小缩放倍数
    max_scale: f32 = 3.0, // 最大缩放倍数
    mod_key: []const u8 = "left_alt", // 组合键的 Mod 键
    sort: []const u8 = "name", // 文件排序方式
    screenshot: Screenshot = .{
        .format = "png",
    },
    titlebar: Titlebar = .{
        .custom = true,
        .no_title_text = false,
        .no_file_size = true,
        .no_app_name = true,
        .opacity = 0.25,
    },
    animation: AnimationConfig = .{
        .image_switch = true,
    },
    shaders: ShadersConfig = .{
        .dir = "shaders",
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
    mod_key: sdl.Key, // 加载后解析出的 Mod 键（保证有效）
    sort: Sort, // 加载后解析出的排序方式（保证有效）

    pub inline fn get(self: *const Loaded) *const MainConfig {
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
            return app_env.report(Error.ConfigParseError, @src(), "配置解析失败：{s}", .{@errorName(err)});
        };
        // 附加基础目录路径
        const base_dir = std.fs.path.dirname(p) orelse ".";
        parsed.value.base_dir = try allocator.dupe(u8, base_dir);

        return Loaded{
            .allocator = allocator,
            .config = .{ .parsed = parsed },
            .mod_key = parseModKey(parsed.value.mod_key),
            .sort = parseSort(parsed.value.sort),
        };
    } else {
        const default = MainConfig{};
        return Loaded{
            .allocator = allocator,
            .config = .{ .owned = default },
            .mod_key = parseModKey(default.mod_key),
            .sort = parseSort(default.sort),
        };
    }
}

// 校验配置中的 Mod 键，配置错误时输出警告并回退到默认值
fn parseModKey(name: []const u8) sdl.Key {
    if (sdl.Key.parse(name)) |key| {
        if (std.mem.indexOfScalar(sdl.Key, &MOD_KEYS, key) != null) return key;
    }
    std.log.warn("Invalid mod_key \"{s}\", falling back to default \"{s}\"", .{ name, @tagName(default_mod_key) });
    return default_mod_key;
}

// 校验配置中的排序方式，配置错误时输出警告并回退到默认值
fn parseSort(name: []const u8) Sort {
    return Sort.parse(name) orelse {
        std.log.warn("Invalid sort \"{s}\", falling back to default \"{s}\"", .{ name, @tagName(Sort.default) });
        return Sort.default;
    };
}
