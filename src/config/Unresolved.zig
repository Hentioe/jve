const toml = @import("toml");

pub const ScreenshotConfig = struct {
    dir: ?[]const u8 = null, // 截图保存目录
    format: ?[]const u8 = null, // 截图的输出格式
};

pub const TitlebarConfig = struct {
    custom: ?bool = null, // 是否启用自定义标题栏
    opacity: ?f32 = null, // 标题栏透明度
    hidden_file_size: ?bool = null, // 隐藏图片尺寸
    hidden_app_name: ?bool = null, // 隐藏应用后缀
    hidden_all_text: ?bool = null, // 隐藏全部文字
};

pub const AnimationConfig = struct {
    image_switch: ?bool = null, // 是否启用图片切换动画
};

pub const ShadersConfig = struct {
    dir: ?[]const u8 = null, // 着色器目录
    background: ?[]const u8 = null, // 背景着色器
    custom: ?toml.HashMap(CustomShaderConfig) = null,
};

pub const CustomShaderConfig = struct {
    keybind: []const u8, // 键绑定
};

pub const ModelsConfig = struct {
    dir: ?[]const u8 = null, // 模型目录
    birefnet: ?BiRefNetConfig = null, // BiRefNet 模型配置
    magic_touch: ?MagicTouchConfig = null, // MagicTouch 模型配置
};

pub const BiRefNetConfig = struct {
    standard_model: []const u8, // 标准模型文件
    lite_model: []const u8, // 轻量模型文件
    used_variant: []const u8, // 使用的变体
    disable_memory_optimization: ?bool = null, // 是否禁用内存优化
};

pub const MagicTouchConfig = struct {
    model: []const u8, // MagicTouch 模型文件
};

base_dir: ?[]const u8 = null, // 基础目录（自动设置）
display_mode: ?[]const u8, // 默认显示模式
min_scale: ?f32, // 最小缩放倍数
max_scale: ?f32, // 最大缩放倍数
mod_key: ?[]const u8 = null, // Mod 键
sort: ?[]const u8 = null, // 文件排序方式
screenshot: ScreenshotConfig = .{}, // 截图配置
titlebar: TitlebarConfig = .{}, // 标题栏配置
animation: AnimationConfig = .{}, // 动画配置
shaders: ShadersConfig = .{}, // 着色器配置
models: ModelsConfig = .{}, // 模型配置
