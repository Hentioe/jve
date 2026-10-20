const Overflow = @import("enums.zig").Overflow;

// 文字片段着色器 Uniforms
pub const TextUniforms = extern struct {
    color: [4]f32, // RGBA
    debug: bool, // 为 true 时输出红色背景，便于观察 quad 的位置与大小
    _padding: [3]u8 = .{ 0, 0, 0 }, // 补齐到 4 字节，确保与 cbuffer 布局一致

    // 从 libass 的 ASS_Image.color（0xRRGGBBAA，低字节为 ASS alpha：0x00 不透明）
    // 解码为归一化 RGBA（常规 alpha：0x00 全透明）
    pub fn fromColor(color: u32, debug: bool) TextUniforms {
        const a: f32 = @floatFromInt(255 - (color & 0xFF));
        const r: f32 = @floatFromInt((color >> 24) & 0xFF);
        const g: f32 = @floatFromInt((color >> 16) & 0xFF);
        const b: f32 = @floatFromInt((color >> 8) & 0xFF);
        return .{
            .color = .{ r / 255.0, g / 255.0, b / 255.0, a / 255.0 },
            .debug = debug,
        };
    }
};

// 横幅背景片段着色器 Uniforms
pub const BannerUniforms = extern struct {
    color: [4]f32, // RGBA
    band: [2]f32, // uv 空间可见区间：x=上边, y=下边
    debug: bool, // 为 true 时输出红色背景
    _padding: [3]u8 = .{ 0, 0, 0 }, // 补齐到 4 字节，确保与 cbuffer 布局一致
};

// 纯色矩形背景片段着色器 Uniforms
pub const RectUniforms = extern struct {
    color: [4]f32, // RGBA
    rect: [4]f32, // uv 空间矩形：左、上、右、下
    debug: u32, // 非 0 时输出红色背景
    _padding: [3]u32 = .{ 0, 0, 0 }, // std140：补齐到 48 字节，确保与 cbuffer 布局一致
};

// 基础片段着色器 Uniforms
pub const BaseUniforms = extern struct {
    invert: f32, // 0.0 ~ 1.0
    grayscale: f32, // 0.0 为全彩，1.0 为完全灰阶（0.5 为半去色）
    brightness: f32, // 0.0 为正常，正数为增亮，负数为变暗
    contrast: f32, // 1.0 为正常，>1.0 增加对比度
    gamma: f32, // 1.0 为正常
    channel: i32, // 0: 正常全彩, 1: R, 2: G, 3: B, 4: A
};

// 锐化片段着色器 Uniforms
pub const SharpenUniforms = extern struct {
    strength: f32,
    _align: f32 = 0.0, // std140：float2 需要 8 字节对齐
    texture_size: [2]f32,
};

// 模糊片段着色器 Uniforms
pub const BlurUniforms = extern struct {
    texel_size: [2]f32,
    direction: [2]f32,
    blur_intensity: f32,
};

// 雾化片段着色器 Uniforms
pub const FogUniforms = extern struct {
    time: f32, // 时间戳 (秒)
};

// 超出尺寸提示片段着色器 Uniforms
pub const OverflowUniforms = extern struct {
    direction: f32, // 位掩码：1=横向(左右)，2=纵向(上下)，3=全部
    thickness: f32 = 5.0, // 边缘提示的厚度（像素）
    alpha: f32, // 整体透明度（用于淡出）

    pub fn init(overflow: Overflow, alpha: f32) OverflowUniforms {
        return .{
            .direction = switch (overflow) {
                .none => 0.0,
                .horizontal => 1.0,
                .vertical => 2.0,
                .both => 3.0,
            },
            .alpha = alpha,
        };
    }
};

// 标记顶点着色器 Uniforms
pub const MarkerVertUniforms = extern struct {
    ndc_x: f32,
    ndc_y: f32,

    pub fn fromViewportPoint(x: f32, y: f32, width: i32, height: i32) MarkerVertUniforms {
        const f_width: f32 = @floatFromInt(width);
        const f_height: f32 = @floatFromInt(height);
        const ndc_x = (x / f_width) * 2.0 - 1.0;
        const ndc_y = 1.0 - (y / f_height) * 2.0; // 注意 Y 轴翻转
        return MarkerVertUniforms{ .ndc_x = ndc_x, .ndc_y = ndc_y };
    }
};

pub const MarkerFragUniforms = extern struct {
    radius: f32, // 整体圆外径 (像素)
    border_width: f32, // 白色外边框厚度 (像素)
};
