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

pub const ShaderPair = struct {
    vert: ?*c.SDL_GPUShader,
    frag: ?*c.SDL_GPUShader,
};

pub const FogUniforms = extern struct {
    time: f32, // 4 字节：时间戳 (秒)
    padding: [3]f32 = .{ 0.0, 0.0, 0.0 }, // 12 字节：填充数据，确保结构体总体大小为 16 字节（16-byte / vec4 对齐）
};
