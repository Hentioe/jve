const sdl = @import("sdl");
const c = sdl.c;
const config = @import("../config.zig");
const Self = @This();

key: sdl.Keycode,
pressed: bool = false,

pub fn init(key: sdl.Keycode) Self {
    return Self{ .key = key };
}

// 配置中的 Mod 键到 SDL 按键的映射
pub fn keycode(kind: config.loader.ModKey) sdl.Keycode {
    return switch (kind) {
        .left_alt => sdl.K._LALT,
        .right_alt => sdl.K._RALT,
        .left_ctrl => sdl.K._LCTRL,
        .right_ctrl => sdl.K._RCTRL,
        .left_shift => sdl.K._LSHIFT,
        .right_shift => sdl.K._RSHIFT,
        .left_gui => sdl.K._LGUI,
        .right_gui => sdl.K._RGUI,
    };
}

// 根据输入类型（方向），自动管理 pressed 状态
pub fn input(self: *Self, _type: u32) void {
    if (_type == c.SDL_EVENT_KEY_DOWN) {
        self.pressed = true;
    } else if (_type == c.SDL_EVENT_KEY_UP) {
        self.pressed = false;
    }
}

pub fn down(self: *Self) void {
    self.pressed = true;
}

pub fn up(self: *Self) void {
    self.pressed = false;
}

pub fn pressedAndInput(self: *const Self, event: c.SDL_Event, _type: u32, key: sdl.Keycode) bool {
    return self.pressed and event.type == _type and event.key.key == key;
}

pub fn pressedAndKeyDown(self: *const Self, event: c.SDL_Event, key: sdl.Keycode) bool {
    return self.pressedAndInput(event, c.SDL_EVENT_KEY_DOWN, key);
}
