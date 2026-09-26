const std = @import("std");
const c = @import("c.zig").c;
const Self = @This();

key: c.SDL_Keycode,
pressed: bool = false,

pub fn init(key: c.SDL_Keycode) Self {
    return Self{ .key = key };
}

// 根据输入类型（方向），自动管理 pressed 状态
pub fn inputType(self: *Self, _type: u32) void {
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
