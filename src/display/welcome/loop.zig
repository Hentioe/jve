const sdl = @import("sdl");
const ui = @import("../../ui.zig");
const RenderDeps = @import("RenderDeps.zig");
const events = @import("events.zig");
const Delta = @import("../Delta.zig");
const State = @import("State.zig");
const frame = @import("frame.zig");
const Error = @import("../errors.zig").Error;

pub fn run(deps: *RenderDeps, context: *events.Context) Error!void {
    var event: sdl.Event = undefined;
    var delta: Delta = .init();
    var state: State = .init(&delta);
    context.bindEvents(&state);

    while (state.running) {
        delta.update(); // 计算 delta

        if (sdl.waitEvent(&event))
            handleEvent(&event, &state, deps);
        while (sdl.pollEvent(&event))
            handleEvent(&event, &state, deps);

        try frame.render(deps, &state);
    }
}

pub fn handleEvent(event: *sdl.Event, state: *State, deps: *RenderDeps) void {
    events.handle(event, state); // 处理全局通用事件
    if (ui.Event.fromSdl(event)) |ui_event| { // 构造 ui 事件结构体
        // 分发 ui 事件给所有 widget
        for (deps.widgets) |*w| w.event(&ui_event);
        deps.banner.event(&ui_event);
    }
}
