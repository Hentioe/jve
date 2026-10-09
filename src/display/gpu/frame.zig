const std = @import("std");
const sdl = @import("sdl");
const h = @import("sdl").h;
const shared = @import("shared");
const structs = @import("../structs.zig");
const Screenshot = @import("../Screenshot.zig");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const Error = @import("../errors.zig").Error;

const Size2D = shared.Size2D;
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
    const cmd_buf = try device.acquireGPUCommandBuffer();
    // 开启 Render Pass
    const base_color_target: sdl.c.SDL_GPUColorTargetInfo = .{
        .texture = state.tex_src,
        .load_op = sdl.c.SDL_GPU_LOADOP_CLEAR,
        .store_op = sdl.c.SDL_GPU_STOREOP_STORE,
        .clear_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };
    const render_pass = sdl.c.SDL_BeginGPURenderPass(cmd_buf, &base_color_target, 1, null);
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
    };
    // 将参数推送到片段着色器的 slot 0
    sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &base_uniforms, @sizeOf(BaseUniforms));
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
                const new_mask = try deps.uploader.uploadTexture(&deps.offscreen_info, mask_ptr, mask_size);
                try deps.uploader.submit();
                if (state.tex_mask) |tex| device.releaseGPUTexture(tex); // 释放旧遮罩纹理
                state.tex_mask = new_mask;
                std.log.info("Task result read complete", .{});
            },
            .failure => |err| std.log.err("Task failed: {}", .{err}),
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
            pl.bindWithMaskTex(cmd_buf, state.tex_dst, state.tex_src, state.tex_mask, deps.sampler, &deps.verts_binding);
        } else {
            pl.bind(cmd_buf, state.tex_dst, state.tex_src, deps.sampler, &deps.verts_binding);
        }
        if (pl.effect == .sharpen) {
            // 传递锐化参数
            const uniforms: SharpenUniforms = .{
                .strength = state.slide_value,
                .texture_size = .{ @floatFromInt(deps.image.shape.w), @floatFromInt(deps.image.shape.h) },
            };
            sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &uniforms, @sizeOf(SharpenUniforms));
        } else if (pl.effect == .blur_x or pl.effect == .blur_y) {
            // 传递模糊参数
            const uniforms: BlurUniforms = .{
                .blur_intensity = -state.slide_value, // 从负数转换而来
                .texel_size = .{ texel_size_w, texel_size_h },
                .direction = if (pl.effect == .blur_x) hor_float2 else ver_float2, // 横向或纵向模糊
            };
            sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &uniforms, @sizeOf(BlurUniforms));
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
            pl.bind(cmd_buf, state.tex_dst, state.tex_src, deps.sampler, &deps.verts_binding);
            pl.draw();
            pl.end();
            const tmp = state.tex_src;
            state.tex_src = state.tex_dst;
            state.tex_dst = tmp;
        }
    }

    // 获取当前帧的 Swapchain 纹理
    var swapchain_texture: ?*sdl.c.SDL_GPUTexture = null;
    if (sdl.c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, deps.window.sdl_window, @constCast(&swapchain_texture), null, null)) {
        if (swapchain_texture != null) {
            // 开启屏幕渲染
            try deps.onscreen.begin(cmd_buf, swapchain_texture);
            // 绘制棋盘格
            deps.checkerboard.bind(deps.onscreen.render_pass); // 绑定到屏幕通道
            deps.checkerboard.draw();
            // 重新绑定屏幕管线，绘制内容（图片 + 后处理）
            deps.onscreen.bind();
            deps.onscreen.draw(state.tex_src, deps.sampler);
            // 在屏幕之上继续添加新内容
            if (state.marker_pos) |pos| {
                // 绘制标记
                deps.marker.bind(deps.onscreen.render_pass);
                // 传递标记位置：事件坐标基于视口（可能是缩放后的窗口），不可直接用图片尺寸算 NDC
                const viewport_size = try deps.window.currentSize();
                const marker_loc_uniforms: MarkerVertUniforms = .fromViewportPoint(pos.x, pos.y, viewport_size.w, viewport_size.h);
                deps.marker.pushVertexUniforms(cmd_buf, 0, &marker_loc_uniforms, @sizeOf(MarkerVertUniforms));
                // 传递标记大小
                const marker_size_uniforms: MarkerFragUniforms = .{ .radius = State.marker_radius, .border_width = 2.0 };
                deps.marker.pushFragmentUniforms(cmd_buf, 0, &marker_size_uniforms, @sizeOf(MarkerFragUniforms));
                // 绘制标记
                deps.marker.draw();
            }
            if (state.overflow_hint.isRunning()) {
                // 在雾效果之前绘制超出提示（屏幕边缘的红色渐变）
                deps.overflow.bindScreen(deps.onscreen.render_pass, &deps.verts_binding);
                const overflow_uniforms = OverflowUniforms.init(deps.window.overflow, state.overflow_hint.alpha);
                sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &overflow_uniforms, @sizeOf(OverflowUniforms));
                deps.overflow.draw();
            }
            if (state.is_busy) {
                // 显示雾（不采样纹理，仅使用 uniform）
                deps.fog.bindScreen(deps.onscreen.render_pass, &deps.verts_binding);
                const fog_uniforms = FogUniforms{ .time = @as(f32, @floatFromInt(sdl.c.SDL_GetTicks())) / 1000.0 };
                sdl.c.SDL_PushGPUFragmentUniformData(cmd_buf, 0, &fog_uniforms, @sizeOf(FogUniforms));
                deps.fog.draw();
            }
            deps.onscreen.end();
        }
    }
    // 提交命令，渲染到屏幕
    try h.check(sdl.c.SDL_SubmitGPUCommandBuffer(cmd_buf));

    // 处理截图保存和复制
    if (state.save_screenshot or state.copy_screenshot) {
        // 创建截图器
        var screenshot = Screenshot.init(
            deps.allocator,
            device,
            state.tex_src,
            &deps.image,
        ) catch |err| fallback: {
            std.log.err("Failed to create screenshot: {}", .{err});
            break :fallback null;
        };
        if (screenshot) |*s| {
            defer s.deinit();
            if (state.save_screenshot) s.saveToFile() catch |err| std.log.err("Failed to save screenshot: {}", .{err});
            if (state.copy_screenshot) s.copyToClipboard();
        }

        // 重置控制参数
        state.save_screenshot = false;
        state.copy_screenshot = false;
    }
}
