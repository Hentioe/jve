const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const UnResolved = @import("UnResolved.zig");
const Keybinding = @import("Keybinding.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

pub const DEFAULT_MOD_KEY: sdl.Key = .left_alt;
pub const DEFAULT_MIN_SCALE: f32 = 0.5;
pub const DEFAULT_MAX_SCALE: f32 = 3.0;
pub const DEFAULT_TITLEBAR_CUSTOM: bool = true;
pub const DEFAULT_TITLEBAR_OPACITY: f32 = 0.15;
pub const DEFAULT_TITLEBAR_HIDDEN_FILE_SIZE: bool = true;
pub const DEFAULT_TITLEBAR_HIDDEN_APP_NAME: bool = true;
pub const DEFAULT_TITLEBAR_HIDDEN_ALL_TEXT: bool = false;
pub const DEFAULT_IMAGE_SWITCH_ANIMATION: bool = true;
pub const DEFAULT_SHADERS_DIR: []const u8 = "shaders";
pub const DEFAULT_MODELS_DIR: []const u8 = "models";

pub const DisplayMode = enum {
    gpu,
    preview,

    pub const default: DisplayMode = .gpu;

    /// 将配置字符串映射为显示模式，无法识别时返回 `null`。
    pub fn parse(name: []const u8) ?DisplayMode {
        return std.meta.stringToEnum(DisplayMode, name);
    }
};

pub const Sort = enum {
    name, // 按名称排序
    created_desc, // 按创建时间降序排序
    created_asc, // 按创建时间升序排序
    modified_desc, // 按修改时间降序排序
    modified_asc, // 按修改时间升序排序

    pub const default: Sort = .name;

    /// 将配置字符串映射为排序方式，无法识别时返回 `null`。
    pub fn parse(name: []const u8) ?Sort {
        return std.meta.stringToEnum(Sort, name);
    }
};

pub const Screenshot = struct {
    dir: ?[]const u8, // 截图保存目录
    format: ScreenshotFormat, // 截图的输出格式

    pub const default: Screenshot = .{
        .dir = null,
        .format = ScreenshotFormat.default,
    };
};

pub const ScreenshotFormat = enum {
    png,
    jpg,
    avif,

    pub const default: ScreenshotFormat = .png;

    /// 将配置字符串映射为截图格式，无法识别时返回 `null`。
    pub fn parse(name: []const u8) ?ScreenshotFormat {
        return std.meta.stringToEnum(ScreenshotFormat, name);
    }

    pub fn format(self: *const ScreenshotFormat, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s}", .{@tagName(self.*)});
    }
};

pub const Titlebar = struct {
    custom: bool, // 是否启用自定义标题栏
    opacity: f32, // 标题栏透明度
    hidden_file_size: bool, // 是否不显示图片尺寸
    hidden_app_name: bool, // 是否不显示应用后缀
    hidden_all_text: bool, // 是否不显示全部文字

    pub const default: Titlebar = .{
        .custom = true,
        .opacity = DEFAULT_TITLEBAR_OPACITY,
        .hidden_file_size = true,
        .hidden_app_name = true,
        .hidden_all_text = false,
    };
};

pub const Animation = struct {
    image_switch: bool, // 是否启用图片切换动画

    pub const default: Animation = .{ .image_switch = DEFAULT_IMAGE_SWITCH_ANIMATION };
};

pub const Shaders = struct {
    dir: []const u8, // 着色器目录
    background: ?[]const u8, // 背景着色器
    custom: ?std.StringHashMap(CustomShader), // 自定义着色器配置

    pub const default: Shaders = .{
        .dir = DEFAULT_SHADERS_DIR,
        .background = null,
        .custom = null,
    };
};

pub const CustomShader = struct {
    keybinding: Keybinding, // 键绑定
};

pub const Models = struct {
    dir: []const u8, // 模型目录
    birefnet: ?BiRefNet, // BiRefNet 模型配置
    magic_touch: ?MagicTouch, // MagicTouch 模型配置

    pub const default: Models = .{
        .dir = DEFAULT_MODELS_DIR,
        .birefnet = null,
        .magic_touch = null,
    };
};

pub const BiRefNet = struct {
    standard_model: []const u8, // 标准模型文件
    lite_model: []const u8, // 轻量模型文件
    used_variant: BiRefNetVariant, // 使用的变体
    disable_memory_optimization: bool, // 是否禁用内存优化
};

pub const BiRefNetVariant = enum {
    standard,
    lite,

    /// 将配置字符串映射为 BiRefNet 变体，无法识别时返回 `null`。
    pub fn parse(name: []const u8) ?BiRefNetVariant {
        return std.meta.stringToEnum(BiRefNetVariant, name);
    }
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

allocator: Allocator,
arena: ArenaAllocator,
base_dir: ?[]const u8, // 基础目录
display_mode: DisplayMode, // 默认显示模式
min_scale: f32, // 最小缩放
max_scale: f32, // 最大缩放
mod_key: sdl.Key, // 修饰键
sort: Sort, // 文件排序方式
screenshot: Screenshot, // 截图配置
titlebar: Titlebar, // 标题栏配置
animation: Animation, // 动画配置
shaders: Shaders, // 着色器配置
models: Models, // 模型配置

pub fn default(allocator: Allocator) Self {
    return Self{
        .allocator = allocator,
        .arena = ArenaAllocator.init(allocator),
        .base_dir = null,
        .display_mode = DisplayMode.default,
        .min_scale = DEFAULT_MIN_SCALE,
        .max_scale = DEFAULT_MAX_SCALE,
        .mod_key = DEFAULT_MOD_KEY,
        .sort = Sort.default,
        .screenshot = Screenshot.default,
        .titlebar = Titlebar.default,
        .animation = Animation.default,
        .shaders = Shaders.default,
        .models = Models.default,
    };
}

pub fn resolve(allocator: Allocator, config: ?UnResolved) Error!Self {
    if (config == null) return default(allocator);
    const loaded = config.?;
    var arena = ArenaAllocator.init(allocator);
    const base_dir = loaded.base_dir;
    const display_mode = resolveDisplayMode(loaded.display_mode);
    const min_scale = loaded.min_scale;
    const max_scale = loaded.max_scale;
    const mod_key = resolveModKey(loaded.mod_key);
    const sort = resolveSort(loaded.sort);
    const screenshot = resolveScreenshot(loaded.screenshot);
    const titlebar = resolveTitlebar(loaded.titlebar);
    const animation = resolveAnimation(loaded.animation);
    const shaders = try resolveShaders(allocator, arena.allocator(), loaded.shaders);
    const models = try resolveModels(loaded.models);

    return Self{
        .allocator = allocator,
        .arena = arena,
        .base_dir = base_dir,
        .display_mode = display_mode,
        .min_scale = min_scale,
        .max_scale = max_scale,
        .mod_key = mod_key,
        .sort = sort,
        .screenshot = screenshot,
        .titlebar = titlebar,
        .animation = animation,
        .shaders = shaders,
        .models = models,
    };
}

pub fn deinit(self: *Self) void {
    if (self.shaders.custom) |*c| c.deinit();
    self.arena.deinit();
}

fn resolveDisplayMode(display_mode: []const u8) DisplayMode {
    if (DisplayMode.parse(display_mode)) |mode| {
        return mode;
    } else {
        std.log.warn("Unrecognized display mode: \"{s}\", falling back to default: \"{s}\"", .{ display_mode, @tagName(DisplayMode.default) });
        return DisplayMode.default;
    }
}

fn resolveModKey(name: []const u8) sdl.Key {
    if (sdl.Key.parse(name)) |key| {
        if (std.mem.indexOfScalar(sdl.Key, &MOD_KEYS, key) != null) return key;
    }
    std.log.warn("Invalid mod_key \"{s}\", falling back to default: \"{s}\"", .{ name, @tagName(DEFAULT_MOD_KEY) });
    return DEFAULT_MOD_KEY;
}

fn resolveSort(name: []const u8) Sort {
    return Sort.parse(name) orelse {
        std.log.warn("Invalid sort \"{s}\", falling back to default: \"{s}\"", .{ name, @tagName(Sort.default) });
        return Sort.default;
    };
}

fn resolveScreenshot(config: UnResolved.ScreenshotConfig) Screenshot {
    var format: ScreenshotFormat = ScreenshotFormat.default;
    if (config.format) |s| if (ScreenshotFormat.parse(s)) |f| {
        format = f;
    } else {
        std.log.warn("Invalid screenshot format \"{s}\", falling back to default: \"{f}\"", .{ s, ScreenshotFormat.default });
    };

    return Screenshot{
        .dir = config.dir,
        .format = format,
    };
}

fn resolveTitlebar(config: UnResolved.TitlebarConfig) Titlebar {
    return .{
        .custom = config.custom orelse DEFAULT_TITLEBAR_CUSTOM,
        .opacity = config.opacity orelse DEFAULT_TITLEBAR_OPACITY,
        .hidden_app_name = config.hidden_app_name orelse DEFAULT_TITLEBAR_HIDDEN_APP_NAME,
        .hidden_file_size = config.hidden_file_size orelse DEFAULT_TITLEBAR_HIDDEN_FILE_SIZE,
        .hidden_all_text = config.hidden_all_text orelse DEFAULT_TITLEBAR_HIDDEN_ALL_TEXT,
    };
}

fn resolveAnimation(config: UnResolved.AnimationConfig) Animation {
    return .{
        .image_switch = config.image_switch,
    };
}

fn resolveShaders(gap: Allocator, arena: Allocator, config: UnResolved.ShadersConfig) Error!Shaders {
    var custom_shaders: ?std.StringHashMap(CustomShader) = null;
    if (config.custom) |custom| {
        var iter = custom.map.iterator();
        var tmp = std.StringHashMap(CustomShader).init(gap);
        while (iter.next()) |kv| {
            const key = try arena.dupe(u8, kv.key_ptr.*);
            const value: CustomShader = .{
                .keybinding = try Keybinding.parse(kv.value_ptr.keybind),
            };
            try tmp.put(key, value);
        }
        custom_shaders = tmp;
    }
    return .{
        .dir = config.dir orelse DEFAULT_SHADERS_DIR,
        .background = config.background,
        .custom = custom_shaders,
    };
}

fn resolveModels(config: UnResolved.ModelsConfig) Error!Models {
    var birefnet: ?BiRefNet = null;
    if (config.birefnet) |b| {
        birefnet = .{
            .standard_model = b.standard_model,
            .lite_model = b.lite_model,
            .used_variant = BiRefNetVariant.parse(b.used_variant) orelse return Error.BiRefNetVariantInvalid,
            .disable_memory_optimization = b.disable_memory_optimization orelse false,
        };
    }
    var magic_touch: ?MagicTouch = null;
    if (config.magic_touch) |m| {
        magic_touch = .{
            .model = m.model,
        };
    }
    return .{
        .dir = config.dir orelse DEFAULT_MODELS_DIR,
        .birefnet = birefnet,
        .magic_touch = magic_touch,
    };
}
