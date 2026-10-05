const c = @import("c.zig").c;
const config = @import("config");
const Self = @This();

key: c.SDL_Keycode,
pressed: bool = false,

pub fn init(key: c.SDL_Keycode) Self {
    return Self{ .key = key };
}

// 配置中的 Mod 键到 SDL 按键的映射
pub fn keycode(kind: config.loader.ModKey) c.SDL_Keycode {
    return switch (kind) {
        .left_alt => c.SDLK_LALT,
        .right_alt => c.SDLK_RALT,
        .left_ctrl => c.SDLK_LCTRL,
        .right_ctrl => c.SDLK_RCTRL,
        .left_shift => c.SDLK_LSHIFT,
        .right_shift => c.SDLK_RSHIFT,
        .left_gui => c.SDLK_LGUI,
        .right_gui => c.SDLK_RGUI,
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

pub fn pressedAndInput(self: *const Self, event: c.SDL_Event, _type: u32, key: c.SDL_Keycode) bool {
    return self.pressed and event.type == _type and event.key.key == key;
}

pub fn pressedAndKeyDown(self: *const Self, event: c.SDL_Event, key: c.SDL_Keycode) bool {
    return self.pressedAndInput(event, c.SDL_EVENT_KEY_DOWN, key);
}
