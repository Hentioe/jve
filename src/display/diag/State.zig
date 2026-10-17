const Delta = @import("../Delta.zig");
const Self = @This();

running: bool = true,
delta: *const Delta,

pub fn init(delta: *const Delta) Self {
    return Self{
        .delta = delta,
    };
}
