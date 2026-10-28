const std = @import("std");
const sdl = @import("sdl");
const app_env = @import("../../app_env.zig");
const ui = @import("../../ui.zig");
const tasks = @import("tasks.zig");
const Io = std.Io;
const Delta = @import("../Delta.zig");
const RenderDeps = @import("RenderDeps.zig");
const events = @import("events.zig");
const State = @import("State.zig");
const frame = @import("frame.zig");
const ExitAction = @import("../enums.zig").ExitAction;
const Error = @import("../errors.zig").Error;

/// 临时诊断：首次循环阻塞与首次渲染耗时只输出一次
var first_stall_logged = false;
var first_render_logged = false;

pub fn run(_: Io, deps: *RenderDeps, ui_ctx: *events.UIContext) Error!ExitAction {
    var event: sdl.c.SDL_Event = undefined;
    var delta: Delta = .init();
    var state: State = .init(deps, &delta);
    defer state.deinit();
    // 强制任务使用基于线程池的 io
    var threaded = Io.Threaded.init(deps.allocator, .{});
    var task_sched = tasks.Scheduler.init(&threaded);
    defer task_sched.deinit();
    ui_ctx.bindEvents(&state);
    var event_ctx = events.Context{
        .deps = deps,
        .state = &state,
        .task_sched = &task_sched,
    };

    var action: events.EventAction = .none;
    // 确保退出时释放任务与遮罩纹理
    defer {
        if (state.task) |t| t.finish();
        if (state.tex_mask) |tex| deps.device.releaseGPUTexture(tex);
    }

    while (state.running) {
        delta.update(); // 计算 delta
        defer action = .none; // 重置动作

        // 推进提示动画
        if (state.overflow_hint.isRunning()) state.overflow_hint.nextStep(delta.value);
        // 繁忙、提示动画或动图播放时保持渲染循环刷新
        state.dirty = state.is_busy or state.overflow_hint.isRunning() or state.playback.playing;
        // 推进定时器（会更新 dirty）
        state.updateTimers();

        if (!state.dirty) {
            var wait_event: sdl.Event = undefined;
            if (sdl.waitEvent(&wait_event)) {
                event_ctx.handle(&wait_event, &action); // 处理事件
                if (ui.Event.fromSdl(&wait_event)) |ui_event| for (deps.widgets) |*w| w.event(&ui_event); // 分发 ui 事件给所有 widget
            }
            // delta.reset(); // 重置 delta（否则阻塞后唤醒会计算出巨大的 delta 值）
        }

        while (sdl.pollEvent(&event)) {
            event_ctx.handle(&event, &action); // 处理事件
            if (ui.Event.fromSdl(&event)) |ui_event| for (deps.widgets) |*w| w.event(&ui_event); // 分发 ui 事件给所有 widget
        }

        // 根据动作修改状态
        try events.applyAction(action, deps, &state);
        // 检查和处理后台任务
        try events.checkHandleTask(deps, &state);
        // 推进动图帧（必须在渲染之前，保证纹理与当前 PTS 对应）
        advanceAnimation(deps, &state);
        // 检查任务
        for (try task_sched.poll()) |t| {
            switch (t.result) {
                .cstr => |cstr| {
                    if (t.name == .save_screenshot)
                        try state.showSuccess(deps, "截图已保存：{f}", .{cstr});
                },
                .ok => {
                    if (t.name == .copy_screenshot)
                        try state.showSuccess(deps, "已复制到剪切板", .{});
                },
                .err => |err| {
                    try state.showError(deps, "{s}", .{@errorName(err)});
                },
            }
            switch (t.name) {
                .copy_screenshot, .save_screenshot => state.screenshot = .default, // 重置截图状态
            }
        }
        // 执行渲染
        try frame.render(deps, &state);
        // 处理截图保存和复制
        if (!state.screenshot.running and state.screenshot.action != .none) try event_ctx.handleScreenshot();
        // 记录首次渲染完成
        if (!first_render_logged) {
            app_env.traceMark("first_rendering");
            app_env.traceComplete(); // 首次渲染完成，跟踪结束
            first_render_logged = true;
        }
    }

    // 通知状态停止渲染
    try deps.window.hide();
    // 切换模式时，把纹理写入全局缓存
    if (state.toggle) {
        app_env.writer().writeTexture(
            deps.allocator,
            deps.device,
            state.tex_src,
        ) catch |err| std.log.err("Failed to write texture: {}", .{err});
    }

    return if (state.toggle) .toggle else .quit;
}

/// 按累计 PTS 推进动图：仅当帧索引变化时才重新解码并更新纹理。
fn advanceAnimation(deps: *RenderDeps, state: *State) void {
    const animation = if (deps.animation) |*a| a else return;
    const index = state.playback.sync(animation, sdl.getTicks()) orelse return;
    const view = animation.frameAt(index) catch |err| {
        std.log.err("Failed to decode animation frame {d}: {}", .{ index, err });
        state.playback.setPlaying(sdl.getTicks(), false);
        return;
    };
    deps.updateFrame(view) catch |err| {
        std.log.err("Failed to upload animation frame {d}: {}", .{ index, err });
        state.playback.setPlaying(sdl.getTicks(), false);
        return;
    };
    state.dirty = true;
}
