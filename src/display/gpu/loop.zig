const std = @import("std");
const sdl = @import("sdl");
const app_env = @import("../../app_env.zig");
const ui = @import("../../ui.zig");
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

pub fn run(deps: *RenderDeps, context: *events.Context) Error!ExitAction {
    var event: sdl.c.SDL_Event = undefined;
    var delta: Delta = .init();
    var state: State = .init(deps, &delta);
    context.bindEvents(&state);

    var action: events.EventAction = .none;
    // 确保退出时释放任务与遮罩纹理
    defer {
        if (state.task) |t| t.finish();
        if (state.tex_mask) |tex| deps.device.releaseGPUTexture(tex);
    }

    var last_iteration_tick: ?u64 = null;

    while (state.running) {
        const iteration_tick = sdl.getTicks();
        if (!first_stall_logged and state.playback.playing) if (last_iteration_tick) |last| {
            const gap = iteration_tick - last;
            if (gap >= 50) {
                first_stall_logged = true;
                std.log.debug("First loop stall: {d} ms since previous iteration", .{gap});
            }
        };
        last_iteration_tick = iteration_tick;

        // 计算 delta
        delta.update();
        defer action = .none; // 重置动作
        // 推进提示动画
        if (state.overflow_hint.isRunning()) state.overflow_hint.nextStep(delta.value);
        // 繁忙、提示动画或动图播放时保持渲染循环刷新
        state.dirty = state.is_busy or state.overflow_hint.isRunning() or state.playback.playing;

        if (!state.dirty) {
            var wait_event: sdl.Event = undefined;
            if (sdl.c.SDL_WaitEvent(&wait_event)) {
                events.handle(&wait_event, &action, &state); // 从事件中更新动作
                if (ui.Event.fromSdl(&wait_event)) |ui_event| { // 阻塞唤醒的事件同样要分发给 widget
                    for (deps.widgets) |*w| w.event(&ui_event);
                }
            }
            delta.reset(); // 重置 delta（否则阻塞后唤醒会计算出巨大的 delta 值）
        }

        while (sdl.c.SDL_PollEvent(&event)) {
            events.handle(&event, &action, &state); // 从事件中更新动作
            if (ui.Event.fromSdl(&event)) |ui_event| { // 构造 ui 事件结构体
                // 分发 ui 事件给所有 widget
                for (deps.widgets) |*w| w.event(&ui_event);
            }
        }

        // 根据动作修改状态
        try events.apply(deps, &action, &state);
        // 推进动图帧（必须在渲染之前，保证纹理与当前 PTS 对应）
        advanceAnimation(deps, &state);
        // 根据状态执行渲染
        try frame.render(deps, &state);
        if (!first_render_logged) {
            const render_started = sdl.getTicks();
            std.log.debug("First frame render took {d} ms", .{sdl.getTicks() - render_started});
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
