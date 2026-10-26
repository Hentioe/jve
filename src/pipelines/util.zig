const std = @import("std");
const sdl = @import("sdl");
const zeroInit = std.mem.zeroInit;
const c = sdl.c;
const Error = @import("errors.zig").Error;
const Gpu = sdl.Gpu;
const ShaderPair = @import("structs.zig").ShaderPair;

pub fn createPipeline(
    gpu: *const Gpu,
    shader_pair: ShaderPair,
    vert_buffer_desc: *const c.SDL_GPUVertexBufferDescription,
    vert_attrs: *const [2]c.SDL_GPUVertexAttribute,
    color_target_desc: *const c.SDL_GPUColorTargetDescription,
) Error!*c.SDL_GPUGraphicsPipeline {
    // 其余字段留空：primitive_type = TRIANGLELIST、光栅化/多重采样/深度模板状态取默认零值、props = 0
    const pipeline_info = zeroInit(sdl.GPUGraphicsPipelineCreateInfo, .{
        // 编译好的顶点着色器
        .vertex_shader = shader_pair.vert,
        // 编译好的片段着色器
        .fragment_shader = shader_pair.frag,
        // 顶点输入布局
        .vertex_input_state = zeroInit(sdl.GPUVertexInputState, .{
            // 顶点缓冲数量与描述（槽位、步长、输入率）
            .num_vertex_buffers = 1,
            .vertex_buffer_descriptions = vert_buffer_desc,
            // 顶点属性数量与属性表（位置 + UV）
            .num_vertex_attributes = 2,
            .vertex_attributes = vert_attrs,
        }),
        // 渲染目标信息（外层 zeroInit 递归清零缺省字段）
        .target_info = .{
            // 颜色目标数量：1
            .num_color_targets = 1,
            // 颜色目标描述（格式与混合状态）
            .color_target_descriptions = color_target_desc,
        },
    });
    return try gpu.createGPUGraphicsPipeline(&pipeline_info);
}
