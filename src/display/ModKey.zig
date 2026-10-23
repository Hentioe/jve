const sdl = @import("sdl");
const c = sdl.c;
const Self = @This();

key: sdl.Key,
pressed: bool = false,

pub fn init(key: sdl.Key) Self {
    return Self{ .key = key };
}

// 根据输入类型（方向），自动管理 pressed 状态
pub fn input(self: *Self, event_type: u32) void {
    if (event_type == c.SDL_EVENT_KEY_DOWN) {
        self.pressed = true;
    } else if (event_type == c.SDL_EVENT_KEY_UP) {
        self.pressed = false;
    }
}

pub fn down(self: *Self) void {
    self.pressed = true;
}

pub fn up(self: *Self) void {
    self.pressed = false;
}

pub fn pressedAndInput(self: *const Self, event: sdl.Event, event_type: u32, key: sdl.Key) bool {
    return self.pressed and event.type == event_type and key.matches(event.key.key);
}

pub fn pressedAndKeyDown(self: *const Self, event: sdl.Event, key: sdl.Key) bool {
    return self.pressedAndInput(event, c.SDL_EVENT_KEY_DOWN, key);
}
