const c = @import("sdl").c;
const Overflow = @import("enums.zig").Overflow;

// 定义顶点与 UV 坐标
pub const Vertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

pub const ShaderPair = struct {
    vert: *c.SDL_GPUShader,
    frag: *c.SDL_GPUShader,
};

// 基础片段着色器 Uniforms
pub const BaseUniforms = extern struct {
    invert: f32, // 0.0 ~ 1.0
    grayscale: f32, // 0.0 为全彩，1.0 为完全灰阶（0.5 为半去色）
    brightness: f32, // 0.0 为正常，正数为增亮，负数为变暗
    contrast: f32, // 1.0 为正常，>1.0 增加对比度
    gamma: f32, // 1.0 为正常
    channel: i32, // 0: 正常全彩, 1: R, 2: G, 3: B, 4: A
    _padding: [2]f32 = .{ 0.0, 0.0 }, // 补齐 16 字节对齐 (5 * 4 = 20 字节，加 12 字节凑齐 32 字节)
};

// 锐化片段着色器 Uniforms
pub const SharpenUniforms = extern struct {
    strength: f32,
    texture_size: [2]f32,
    _padding: f32 = 0.0,
};

// 模糊片段着色器 Uniforms
pub const BlurUniforms = extern struct {
    texel_size: [2]f32,
    direction: [2]f32,
    blur_intensity: f32,
    _padding: [3]f32 = .{ 0.0, 0.0, 0.0 },
};

// 雾化片段着色器 Uniforms
pub const FogUniforms = extern struct {
    time: f32, // 4 字节：时间戳 (秒)
    _padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // 12 字节：填充数据，确保结构体总体大小为 16 字节（16-byte / vec4 对齐）
};

// 超出尺寸提示片段着色器 Uniforms
pub const OverflowUniforms = extern struct {
    direction: f32, // 位掩码：1=横向(左右)，2=纵向(上下)，3=全部
    thickness: f32 = 5.0, // 边缘提示的厚度（像素）
    alpha: f32, // 整体透明度（用于淡出）
    _padding: f32 = 0.0,

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
    _padding: [2]f32 = .{ 0.0, 0.0 }, // 8 字节：仅用于凑齐 16 字节

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
    _padding: [2]f32 = .{ 0.0, 0.0 }, // 8 字节：仅用于凑齐 16 字节
};
