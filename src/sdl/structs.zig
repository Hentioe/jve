const c = @import("c.zig").c;

pub fn Size(comptime T: type) type {
    return struct {
        w: T,
        h: T,
    };
}

pub const ShaderPair = struct {
    vert: ?*c.SDL_GPUShader,
    frag: ?*c.SDL_GPUShader,
};
