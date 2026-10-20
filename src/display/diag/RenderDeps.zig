const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const consts = @import("../consts.zig");
const Vertex = shared.Vertex;
const Window = @import("../window.zig");
const Device = @import("../../Device.zig");
const shader_loader = @import("../../shader.zig").loader;
const Pipeline = @import("../../pipelines/BasePipeline.zig");
const Widget = @import("../../ui/Widget.zig");
const TextBanner = @import("../../ui/TextBanner.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

allocator: Allocator,
window: *Window,
gpu: *const sdl.Gpu,
widgets: []Widget,
banner: *TextBanner,
bg_pipeline: Pipeline,
bg_verts_buffer: *sdl.GPUBuffer,
bg_verts_binding: sdl.GPUBufferBinding,

pub fn init(allocator: Allocator, window: *Window, gpu: *const sdl.Gpu, widgets: []Widget, banner: *TextBanner) Error!Self {
    const vert_buffer_desc: sdl.GPUVertexBufferDescription = .{ .slot = 0, .pitch = @sizeOf(Vertex), .input_rate = sdl.GPU_VERTEXINPUTRATE_VERTEX };
    const vert_attrs: [2]sdl.GPUVertexAttribute = .{
        .{ .location = 0, .format = sdl.GPU_VERTEXELEMENTFORMAT_FLOAT3, .offset = @offsetOf(Vertex, "x") }, // Position
        .{ .location = 1, .format = sdl.GPU_VERTEXELEMENTFORMAT_FLOAT2, .offset = @offsetOf(Vertex, "u") }, // UV
    };
    const vertex_input_state: sdl.GPUVertexInputState = .{
        .num_vertex_buffers = 1,
        .vertex_buffer_descriptions = &vert_buffer_desc,
        .num_vertex_attributes = 2,
        .vertex_attributes = &vert_attrs,
    };

    // 背景管线
    const vert_shader = try shader_loader.load(gpu, @embedFile("base.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    const frag_shader = try shader_loader.load(gpu, @embedFile("diag.frag.spv"), "main", .fragment, .{ .samplers = 0, .buffers = 0 });
    const bg_pipeline = try Pipeline.init(gpu, window.sdl_window, .{ .vert = vert_shader, .frag = frag_shader }, vertex_input_state);

    // 获取全局上传器
    const uploader = try Device.getUploader();

    // 上传全屏顶点
    const verts = consts.base_verts;
    const verts_size = @sizeOf(Vertex) * verts.len;
    const verts_buffer_info = sdl.GPUBufferCreateInfo{ .usage = sdl.GPU_BUFFERUSAGE_VERTEX, .size = verts_size };
    const bg_verts_buffer = try uploader.uploadBufferBorrowed(&verts_buffer_info, @ptrCast(&verts), verts_size);

    try uploader.submit();

    return Self{
        .allocator = allocator,
        .window = window,
        .gpu = gpu,
        .bg_pipeline = bg_pipeline,
        .bg_verts_buffer = bg_verts_buffer,
        .bg_verts_binding = sdl.GPUBufferBinding{ .buffer = bg_verts_buffer, .offset = 0 },
        .widgets = widgets,
        .banner = banner,
    };
}

pub fn deinit(self: *Self) void {
    self.bg_pipeline.deinit();
    self.gpu.releaseGPUBuffer(self.bg_verts_buffer);
    self.* = undefined;
}
