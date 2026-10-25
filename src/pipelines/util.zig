const std = @import("std");
const c = @import("sdl").c;
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
const ShaderPair = @import("structs.zig").ShaderPair;

pub fn createPipeline(
    gpu: *const Gpu,
    shader_pair: ShaderPair,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) Error!*c.SDL_GPUGraphicsPipeline {
    const pipeline_info: c.SDL_GPUGraphicsPipelineCreateInfo = .{
        .vertex_shader = shader_pair.vert, // 编译好的顶点着色器
        .fragment_shader = shader_pair.frag, // 编译好的片段着色器
        .vertex_input_state = .{
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = vert_buffer_desc,
            .num_vertex_attributes = 2,
            .vertex_attributes = vert_attrs,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = color_target_desc,
            .depth_stencil_format = c.SDL_GPU_TEXTUREFORMAT_INVALID,
            .has_depth_stencil_target = false,
            .padding1 = 0,
            .padding2 = 0,
            .padding3 = 0,
        },
        .rasterizer_state = std.mem.zeroes(c.SDL_GPURasterizerState),
        .multisample_state = std.mem.zeroes(c.SDL_GPUMultisampleState),
        .depth_stencil_state = std.mem.zeroes(c.SDL_GPUDepthStencilState),
        .props = 0,
    };
    return try gpu.createGPUGraphicsPipeline(&pipeline_info);
}
