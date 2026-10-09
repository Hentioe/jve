const sdl = @import("sdl");
const RenderDeps = @import("RenderDeps.zig");
const events = @import("events.zig");
const Delta = @import("../Delta.zig");
const State = @import("State.zig");
const frame = @import("frame.zig");
const ExitAction = @import("../enums.zig").ExitAction;
const Error = @import("../errors.zig").Error;

pub fn run(deps: *RenderDeps) Error!ExitAction {
    var event: sdl.Event = undefined;
    var delta: Delta = .init();
    var state: State = .init(deps, &delta);
    var action: events.EventAction = .none;

    while (state.running) {
        // 计算 delta
        delta.update();
        defer action = .none; // 重置动作

        if (!state.dirty) {
            var wait_event: sdl.Event = undefined;
            if (sdl.c.SDL_WaitEvent(&wait_event)) events.handle(&wait_event, &action, &state);
            delta.reset(); // 重置 delta（否则阻塞后唤醒会计算出巨大的 delta 值）
        }
        // 从事件中更新动作
        while (sdl.c.SDL_PollEvent(&event)) events.handle(&event, &action, &state);

        // 根据动作修改状态
        try events.apply(deps, &action, &state);
        // 根据状态执行渲染
        try frame.render(deps, &state);
    }

    // 缓存控制参数
    state.external_state.target_angle = state.angle.target;
    state.external_state.target_scale = state.scale.target;
    state.external_state.move_offset = state.move_offset;
    // 通知状态停止渲染
    try deps.window.hide();

    return if (state.toggle) .toggle else .quit;
}
