const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const structs = @import("../structs.zig");
const Size2D = shared.Size2D;
const Device = @import("../../Device.zig");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const Error = @import("../errors.zig").Error;
// -- uniforms --
const BaseUniforms = structs.BaseUniforms;
const SharpenUniforms = structs.SharpenUniforms;
const FogUniforms = structs.FogUniforms;
const BlurUniforms = structs.BlurUniforms;
const MarkerVertUniforms = structs.MarkerVertUniforms;
const MarkerFragUniforms = structs.MarkerFragUniforms;
const OverflowUniforms = structs.OverflowUniforms;

pub fn render(deps: *RenderDeps, state: *State) Error!void {
    const device = deps.device;
    // 获取当前帧的 Command Buffer
    const cmd = try device.acquireGPUCommandBuffer();
    // 开启渲染通道
    const base_color_target: sdl.c.SDL_GPUColorTargetInfo = .{
        .texture = state.tex_src,
        .mip_level = 0,
        .layer_or_depth_plane = 0,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
        .load_op = sdl.c.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.c.SDL_GPU_STOREOP_STORE,
        .resolve_texture = null,
        .resolve_mip_level = 0,
        .resolve_layer = 0,
        .cycle = false,
        .cycle_resolve_texture = false,
        .padding1 = 0,
        .padding2 = 0,
    };
    const render_pass = sdl.c.SDL_BeginGPURenderPass(cmd, &base_color_target, 1, null);
    // 绑定图形管线
    sdl.c.SDL_BindGPUGraphicsPipeline(render_pass, deps.base_pipeline);
    // 绑定顶点缓冲区
    sdl.c.SDL_BindGPUVertexBuffers(render_pass, 0, &deps.verts_binding, 1);
    // 绑定图像的像素纹理以及采样器
    const tex_binding: sdl.c.SDL_GPUTextureSamplerBinding = .{ .texture = deps.texture, .sampler = deps.sampler };
    sdl.c.SDL_BindGPUFragmentSamplers(render_pass, 0, &tex_binding, 1);
    // 准备片段着色器的的参数
    const base_uniforms: BaseUniforms = .{
        .invert = if (state.is_inverted) 1.0 else 0.0,
        .brightness = state.brightness,
        .contrast = state.contrast,
        .gamma = state.gamma,
        .grayscale = if (state.is_grayscale) 1.0 else 0.0,
        .channel = state.channel,
    };
    // 将参数推送到片段着色器的 slot 0
    sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &base_uniforms, @sizeOf(BaseUniforms));
    // 绘制矩形 (绘制 6 个顶点 = 2 个三角形)
    sdl.c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
    // 结束渲染通道
    sdl.c.SDL_EndGPURenderPass(render_pass);

    // 检查任务
    if (state.task) |t| if (t.poll() == .done) {
        defer {
            t.finish();
            state.task = null;
            state.is_busy = false;
            state.dirty = false;
        }
        if (t.result) |*res| switch (res.*) {
            .success => |s| {
                std.log.info("Task result is reading...", .{});
                const mask_ptr = s.data_ptr; // 获取遮罩数据指针
                const mask_size: Size2D(u32) = .{ .w = s.width, .h = s.height };
                const uploader = try Device.getUploader();
                const new_mask = try uploader.uploadTextureBorrowed(&deps.offscreen_info, mask_ptr, mask_size);
                try uploader.submit();
                if (state.tex_mask) |tex| device.releaseGPUTexture(tex); // 释放旧遮罩纹理
                state.tex_mask = new_mask;
                std.log.info("Task result read complete", .{});
            },
            .failure => |err| try state.showError(deps, "任务出错：{s}", .{@errorName(err)}),
        };
    };

    // 后处理管线
    const f_shape = deps.image.shape.to(f32);
    const texel_size_w = 1.0 / f_shape.w;
    const texel_size_h = 1.0 / f_shape.h;
    const hor_float2 = .{ 1.0, 0.0 }; // 横方向
    const ver_float2 = .{ 0.0, 1.0 }; // 纵方向
    // 内建管线
    for (deps.builtin()) |pl| {
        // 判断是否进入管线
        if (pl.effect == .sharpen and state.slide_value <= 0) continue; // 没有有效值，跳过
        if ((pl.effect == .blur_x or pl.effect == .blur_y) and state.slide_value >= 0) continue; // 没有有效值，跳过
        if (pl.effect == .mask and state.tex_mask == null) continue; // 没有有效的 mask，跳过
        // 绑定管线
        if (pl.effect == .mask) {
            pl.bindWithMaskTex(cmd, state.tex_dst, state.tex_src, state.tex_mask, deps.sampler, &deps.verts_binding);
        } else {
            pl.bind(cmd, state.tex_dst, state.tex_src, deps.sampler, &deps.verts_binding);
        }
        if (pl.effect == .sharpen) { // 传递锐化参数
            const uniforms: SharpenUniforms = .{
                .strength = state.slide_value,
                .texture_size = .{ @floatFromInt(deps.image.shape.w), @floatFromInt(deps.image.shape.h) },
            };
            sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &uniforms, @sizeOf(SharpenUniforms));
        } else if (pl.effect == .blur_x or pl.effect == .blur_y) { // 传递模糊参数
            const uniforms: BlurUniforms = .{
                .blur_intensity = -state.slide_value, // 从负数转换而来
                .texel_size = .{ texel_size_w, texel_size_h },
                .direction = if (pl.effect == .blur_x) hor_float2 else ver_float2, // 横向或纵向模糊
            };
            sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &uniforms, @sizeOf(BlurUniforms));
        }

        // 绘制管线内容
        pl.draw();
        pl.end();
        // 乒乓交换：把这一轮的输出 dst，作为下一轮的输入 src
        const tmp = state.tex_src;
        state.tex_src = state.tex_dst;
        state.tex_dst = tmp;
    }
    // 自定义管线
    if (state.custom_shader_enabled) {
        for (deps.custom.items) |pl| {
            pl.bind(cmd, state.tex_dst, state.tex_src, deps.sampler, &deps.verts_binding);
            pl.draw();
            pl.end();
            const tmp = state.tex_src;
            state.tex_src = state.tex_dst;
            state.tex_dst = tmp;
        }
    }
    // 手动触发的管线
    if (state.manual) |pl| {
        pl.bind(cmd, state.tex_dst, state.tex_src, deps.sampler, &deps.verts_binding);
        pl.draw();
        pl.end();
        const tmp = state.tex_src;
        state.tex_src = state.tex_dst;
        state.tex_dst = tmp;
    }

    // 截图包含背景：背景作为链上的一趟垫在内容下面
    if (state.screenshot.include_bg) {
        try deps.background.composite(cmd, state.tex_src);
    }

    // 获取当前帧的 Swapchain 纹理
    var tex_swp: ?*sdl.GPUTexture = null;
    if (sdl.c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd, deps.window.sdl_window, @constCast(&tex_swp), null, null)) {
        if (tex_swp != null) {
            // 开启屏幕渲染
            try deps.screen.begin(cmd, tex_swp);
            // tex_src 已包含背景时不再重复绘制
            if (!state.screenshot.include_bg) {
                // 绑定背景管线，绘制背景
                deps.background.bind(deps.screen.render_pass); // 绑定到屏幕通道
                deps.background.draw();
            }
            // 绑定屏幕管线，绘制内容（图片 + 后处理）
            deps.screen.bind();
            deps.screen.draw(state.tex_src, deps.sampler);
            // 在屏幕之上继续添加新内容
            if (state.marker_pos) |pos| {
                // 绘制标记
                deps.marker.bind(deps.screen.render_pass);
                // 传递标记位置：事件坐标基于视口（可能是缩放后的窗口），不可直接用图片尺寸算 NDC
                const viewport_size = try deps.window.currentSize();
                const marker_loc_uniforms: MarkerVertUniforms = .fromViewportPoint(pos.x, pos.y, viewport_size.w, viewport_size.h);
                deps.marker.pushVertexUniforms(cmd, 0, &marker_loc_uniforms, @sizeOf(MarkerVertUniforms));
                // 传递标记大小
                const marker_size_uniforms: MarkerFragUniforms = .{ .radius = State.MARKER_RADIUS, .border_width = 2.0 };
                deps.marker.pushFragmentUniforms(cmd, 0, &marker_size_uniforms, @sizeOf(MarkerFragUniforms));
                // 绘制标记
                deps.marker.draw();
            }
            if (state.overflow_hint.isRunning()) {
                // 在雾效果之前绘制超出提示（屏幕边缘的红色渐变）
                deps.overflow.bindScreen(deps.screen.render_pass, &deps.verts_binding);
                const overflow_uniforms = OverflowUniforms.init(deps.window.overflow, state.overflow_hint.alpha);
                sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &overflow_uniforms, @sizeOf(OverflowUniforms));
                deps.overflow.draw();
            }
            if (state.is_busy) {
                // 显示雾效果（不采样纹理，仅使用 uniform）
                deps.fog.bindScreen(deps.screen.render_pass, &deps.verts_binding);
                const fog_uniforms = FogUniforms{ .time = @as(f32, @floatFromInt(sdl.c.SDL_GetTicks())) / 1000.0 };
                sdl.c.SDL_PushGPUFragmentUniformData(cmd, 0, &fog_uniforms, @sizeOf(FogUniforms));
                deps.fog.draw();
            }
            // 绘制组件
            for (deps.widgets) |*widget| widget.draw(cmd, deps.screen.render_pass);
            // 绘制错误横幅
            if (state.show_error) deps.error_banner.draw(cmd, deps.screen.render_pass);
            // 结束屏幕绘制
            deps.screen.end();
        }
    }
    // 提交命令，渲染到屏幕
    try sdl.h.check(sdl.c.SDL_SubmitGPUCommandBuffer(cmd));
}
