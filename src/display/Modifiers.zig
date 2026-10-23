const std = @import("std");
const sdl = @import("sdl");
const Keybinding = @import("../config.zig").Keybinding;
const WorkingKeys = std.EnumSet(Keybinding.Modifier);
const Self = @This();

working_keys: WorkingKeys,

pub fn init() Self {
    return Self{ .working_keys = .initEmpty() };
}

pub fn input(self: *Self, event: *const sdl.Event) void {
    const key = sdl.Key.from(event.key.key) orelse return;
    const modifier = Keybinding.Modifier.from(key) orelse return;
    if (event.type == sdl.EVENT_KEY_DOWN) {
        std.log.debug("Modifier key pressed: {s}", .{@tagName(modifier)});
        self.working_keys.insert(modifier);
    }

    if (event.type == sdl.EVENT_KEY_UP and self.working_keys.contains(modifier)) {
        std.log.debug("Modifier key released: {s}", .{@tagName(modifier)});
        self.working_keys.remove(modifier);
    }
}

pub fn working(self: *Self, key: sdl.Key) bool {
    const modifier = Keybinding.Modifier.from(key) orelse return false;
    return self.working_keys.contains(modifier);
}
