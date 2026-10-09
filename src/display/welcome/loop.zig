const sdl = @import("sdl");
const RenderDeps = @import("RenderDeps.zig");
const events = @import("events.zig");
const Delta = @import("../Delta.zig");
const State = @import("State.zig");
const frame = @import("frame.zig");
const Error = @import("../errors.zig").Error;

pub fn run(deps: *RenderDeps) Error!void {
    var event: sdl.Event = undefined;
    var delta: Delta = .init();
    var state: State = .init(&delta);

    while (state.running) {
        delta.update(); // 计算 delta

        while (sdl.c.SDL_PollEvent(&event)) {
            events.handle(&event, &state);
        }
        try frame.render(deps, &state);
    }
}
