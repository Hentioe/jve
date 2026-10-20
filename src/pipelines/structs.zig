const sdl = @import("sdl");
const shared = @import("shared");
const Vertex = shared.Vertex;

pub const ShaderPair = struct {
    vert: *sdl.GPUShader,
    frag: *sdl.GPUShader,
};

pub const vertex_buffer_desc: sdl.c.SDL_GPUVertexBufferDescription = .{
    .slot = 0,
    .pitch = @sizeOf(Vertex),
    .input_rate = sdl.c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
};

pub const vertex_attrs: [2]sdl.c.SDL_GPUVertexAttribute = .{
    .{ .location = 0, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
    .{ .location = 1, .format = sdl.c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
};

pub const vertex_input_state: sdl.c.SDL_GPUVertexInputState = .{
    .num_vertex_buffers = 1,
    .vertex_buffer_descriptions = &vertex_buffer_desc,
    .num_vertex_attributes = 2,
    .vertex_attributes = &vertex_attrs,
};
