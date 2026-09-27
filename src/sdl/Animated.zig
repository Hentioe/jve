const std = @import("std");
const c = @import("c.zig").c;
const Self = @This();

const FINISH_EPSILON = 0.001;

current: f32,
target: f32,
step: f32,

pub fn init(current: f32, target: f32, step: f32) Self {
    return Self{
        .current = current,
        .target = target,
        .step = step,
    };
}

pub fn nextStep(self: *Self) void {
    self.current += (self.target - self.current) * self.step;
}

// 是否接近完成
pub fn isNearFinished(self: *const Self) bool {
    return c.SDL_fabsf(self.target - self.current) < FINISH_EPSILON;
}

pub fn finish(self: *Self) void {
    self.current = self.target;
}
