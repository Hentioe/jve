const std = @import("std");
const sdl = @import("sdl");
const Keybinding = @import("../config.zig").Keybinding;
const Modifier = Keybinding.Modifier;
const WorkingKeys = std.EnumSet(Modifier);
const Self = @This();

primary_key: Modifier,
working_keys: WorkingKeys,
primary_pressed_changed: bool = false,

pub fn init(primary_key: Modifier) Self {
    return Self{ .primary_key = primary_key, .working_keys = .initEmpty() };
}

pub fn input(self: *Self, event: *const sdl.Event) void {
    const key = sdl.Key.from(event.key.key) orelse return;
    const modifier = Modifier.from(key) orelse return;
    if (event.type == sdl.EVENT_KEY_DOWN) {
        std.log.debug("Modifier key pressed: {s}", .{@tagName(modifier)});
        self.working_keys.insert(modifier);
        if (modifier == self.primary_key) self.primary_pressed_changed = true;
    }

    if (event.type == sdl.EVENT_KEY_UP and self.working_keys.contains(modifier)) {
        std.log.debug("Modifier key released: {s}", .{@tagName(modifier)});
        self.working_keys.remove(modifier);
        if (modifier == self.primary_key) self.primary_pressed_changed = true;
    }
}

pub fn working(self: *Self, key: sdl.Key) bool {
    const modifier = Modifier.from(key) orelse return false;
    return self.working_keys.contains(modifier);
}

/// 主修饰键是否按下。
pub fn primaryPressed(self: *const Self) bool {
    return self.working_keys.contains(self.primary_key);
}

/// 主修饰键和指定键是否都按下。
pub fn primaryPressedBoth(self: *const Self, event: sdl.Event, key: sdl.Key) bool {
    return self.primaryPressed() and event.type == sdl.EVENT_KEY_DOWN and key.matches(event.key.key);
}

/// 主修饰键状态是否发生变化（访问后会重置状态）。
pub fn takePrimaryPressedChanged(self: *Self) bool {
    if (!self.primary_pressed_changed) return false;
    const changed = self.primary_pressed_changed;
    self.primary_pressed_changed = false;
    return changed;
}
