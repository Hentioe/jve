const sdl = @import("sdl");
const State = @import("State.zig");

pub fn handle(event: *sdl.Event, state: *State) void {
    if (event.type == sdl.EVENT_QUIT) state.running = false;
}
