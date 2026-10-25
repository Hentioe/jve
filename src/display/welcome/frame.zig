const sdl = @import("sdl");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const Error = @import("../errors.zig").Error;

pub fn render(deps: *RenderDeps, _: *const State) Error!void {
    // std.log.info("delta: {}, fps: {}", .{ state.delta.value, state.delta.fps });

    // 获取当前帧的命令缓存区
    const cmd = try deps.gpu.acquireGPUCommandBuffer();
    // 获取交换链纹理
    var tex_swap: ?*sdl.GPUTexture = null;
    const acquired = sdl.Gpu.acquireSwapchainTexture(cmd, deps.window.sdl_window, &tex_swap, null, null);
    // 判定获取失败或纹理为空（如窗口最小化/调整大小期间）
    if (!acquired or tex_swap == null) {
        try sdl.Gpu.submitCommandBuffer(cmd); // 即使不绘制，也必须提交/释放本次命令缓存区
        return;
    }
    var color_target: sdl.c.SDL_GPUColorTargetInfo = .{
        .texture = tex_swap,
        .load_op = sdl.c.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.c.SDL_GPU_STOREOP_STORE,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .clear_color = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 },
        .resolve_texture = null,
        .resolve_mip_level = 0,
        .resolve_layer = 0,
        .cycle = false,
        .cycle_resolve_texture = false,
        .padding1 = 0,
        .padding2 = 0,
    };
    // 开启渲染通道
    const pass = try sdl.Gpu.beginRenderPass(cmd, &color_target, 1, null);
    // 绑定图形管线
    deps.pipeline.bind(pass);
    // 绑定顶点缓冲区
    sdl.c.SDL_BindGPUVertexBuffers(pass, 0, &deps.verts_binding, 1);
    // 绘制矩形 (绘制 6 个顶点 = 2 个三角形)
    sdl.c.SDL_DrawGPUPrimitives(pass, 6, 1, 0, 0);
    // 绘制组件
    for (deps.widgets) |*widget| widget.draw(cmd, pass);
    // 绘制底部横幅（一直显示）
    deps.banner.draw(cmd, pass);
    // 结束渲染通道
    sdl.c.SDL_EndGPURenderPass(pass);
    // 提交命令缓存区
    try sdl.Gpu.submitCommandBuffer(cmd);
}
