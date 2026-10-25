const sdl = @import("sdl");
const shared = @import("shared");
const Vertex = shared.Vertex;
const RectUniforms = @import("../display/structs.zig").RectUniforms;
const base_verts = @import("../display/consts.zig").base_verts;
const Device = @import("../Device.zig");
const RectPipeline = @import("../pipelines/RectPipeline.zig");
const FrameSize = shared.Size2D(i32);
const Error = @import("errors.zig").Error;
const Self = @This();

/// 像素坐标系下的轴对齐矩形（原点为帧左上角）。
pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn toUniform(self: Rect, frame_size: FrameSize) [4]f32 {
        const fw: f32 = @floatFromInt(frame_size.w);
        const fh: f32 = @floatFromInt(frame_size.h);
        return .{
            self.x / fw,
            self.y / fh,
            (self.x + self.w) / fw,
            (self.y + self.h) / fh,
        };
    }
};

/// 单个纯色矩形背景的绘制依赖：全屏 quad 顶点（恒定不变）+ 状态 uniform。
///
/// 与 `BannerDrawer` 对称。顶点固定为铺满屏幕的矩形，真正决定可见区域的是
/// `RectUniforms.rect`（uv 空间的矩形）与颜色，因此矩形位置/尺寸变化时只需更新
/// uniform，无需重建 GPU 资源。
pipeline: *RectPipeline,
verts_buffer: *sdl.c.SDL_GPUBuffer,
verts_binding: sdl.c.SDL_GPUBufferBinding,
uniforms: RectUniforms,

pub fn init(
    pipeline: *RectPipeline,
    frame_size: FrameSize,
    rect: Rect,
    color: [4]f32,
    debug: bool,
) Error!Self {
    const uploader = try Device.getUploader();
    const verts_size: u32 = @intCast(@sizeOf(Vertex) * base_verts.len);
    const verts_buffer_info = sdl.c.SDL_GPUBufferCreateInfo{ .usage = sdl.c.SDL_GPU_BUFFERUSAGE_VERTEX, .size = verts_size, .props = 0 };
    // base_verts 是编译期常量，生命周期贯穿整个程序，无需额外暂存
    const verts_buffer = try uploader.uploadBufferBorrowed(&verts_buffer_info, @ptrCast(&base_verts), verts_size);

    return Self{
        .pipeline = pipeline,
        .verts_buffer = verts_buffer,
        .verts_binding = .{ .buffer = verts_buffer, .offset = 0 },
        .uniforms = rectUniforms(frame_size, rect, color, debug),
    };
}

fn rectUniforms(frame_size: FrameSize, rect: Rect, color: [4]f32, debug: bool) RectUniforms {
    return .{ .color = color, .rect = rect.toUniform(frame_size), .debug = @intFromBool(debug) };
}

/// 更新矩形（像素，帧左上角原点）与颜色。只写 uniform，代价可忽略。
pub fn update(self: *Self, frame_size: FrameSize, rect: Rect, color: [4]f32, debug: bool) void {
    self.uniforms = rectUniforms(frame_size, rect, color, debug);
}

pub fn deinit(self: *Self) void {
    self.pipeline.gpu.releaseGPUBuffer(self.verts_buffer);
    self.* = undefined;
}

/// 在当前 render pass 内绑定共享管线与自身资源并绘制全屏 quad。
pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.pipeline.bind(pass);
    sdl.c.SDL_BindGPUVertexBuffers(pass, 0, &self.verts_binding, 1);
    sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &self.uniforms, @sizeOf(RectUniforms));
    self.pipeline.draw();
}
