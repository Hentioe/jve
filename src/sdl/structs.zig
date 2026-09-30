const c = @import("c.zig").c;

pub fn Size(comptime T: type) type {
    return struct {
        w: T,
        h: T,
    };
}

pub const Point = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

// todo: 被 ShaderPair2 替代
pub const ShaderPair = struct {
    vert: ?*c.SDL_GPUShader,
    frag: ?*c.SDL_GPUShader,
};

pub const ShaderPair2 = struct {
    vert: *c.SDL_GPUShader,
    frag: *c.SDL_GPUShader,
};

pub const FogUniforms = extern struct {
    time: f32, // 4 字节：时间戳 (秒)
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // 12 字节：填充数据，确保结构体总体大小为 16 字节（16-byte / vec4 对齐）
};

pub const MarkerUniforms = extern struct {
    ndc_x: f32,
    ndc_y: f32,
    padding: [2]f32 = .{ 0.0, 0.0 }, // 8 字节：仅用于凑齐 16 字节

    pub fn fromScreen(x: f32, y: f32, screenWidth: i32, screenHeight: i32) MarkerUniforms {
        const f_width: f32 = @floatFromInt(screenWidth);
        const f_height: f32 = @floatFromInt(screenHeight);
        const ndc_x = (x / f_width) * 2.0 - 1.0;
        const ndc_y = 1.0 - (y / f_height) * 2.0; // 注意 Y 轴翻转
        return MarkerUniforms{
            .ndc_x = ndc_x,
            .ndc_y = ndc_y,
            .padding = .{ 0.0, 0.0 },
        };
    }
};
