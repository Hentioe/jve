const sdl = @import("sdl");
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

        while (sdl.c.SDL_PollEvent(&event)) {
            events.handle(&event, &state); // 处理全局通用事件
            if (events.build(&event)) |ui_event| { // 构造 ui 事件结构体
                // 分发 ui 事件给所有 widget
                for (deps.widgets) |*w| w.event(&ui_event);
                deps.banner.event(&ui_event);
            }
        }
        try frame.render(deps, &state);
    }
}
