const c = @import("c.zig").c;
const std = @import("std");

pub fn Size(comptime T: type) type {
    return struct {
        w: T,
        h: T,
    };
}

pub fn Point(comptime T: type) type {
    return struct {
        x: T = std.mem.zeroes(T),
        y: T = std.mem.zeroes(T),
    };
}

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
    _padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // 补齐 16 字节对齐 (5 * 4 = 20 字节，加 12 字节凑齐 32 字节)
};

// 锐化片段着色器 Uniforms
pub const SharpenUniforms = extern struct {
    strength: f32,
    textureSize: [2]f32,
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

// 标记顶点着色器 Uniforms
pub const MarkerUniforms = extern struct {
    ndc_x: f32,
    ndc_y: f32,
    _padding: [2]f32 = .{ 0.0, 0.0 }, // 8 字节：仅用于凑齐 16 字节

    pub fn fromScreen(x: f32, y: f32, screenWidth: i32, screenHeight: i32) MarkerUniforms {
        const f_width: f32 = @floatFromInt(screenWidth);
        const f_height: f32 = @floatFromInt(screenHeight);
        const ndc_x = (x / f_width) * 2.0 - 1.0;
        const ndc_y = 1.0 - (y / f_height) * 2.0; // 注意 Y 轴翻转
        return MarkerUniforms{ .ndc_x = ndc_x, .ndc_y = ndc_y };
    }
};
