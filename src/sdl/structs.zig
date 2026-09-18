const c = @import("c.zig").c;

pub const ShaderPair = struct {
    vert: ?*c.SDL_GPUShader,
    frag: ?*c.SDL_GPUShader,
};
