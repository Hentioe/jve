const std = @import("std");
const c = @import("c.zig").c;
const Self = @This();

const FINISH_EPSILON = 0.001;
const State = enum { running, finished };

current: f64,
target: f64,
step: f64,
state: State,

pub fn init(current: f64, target: f64, step: f64) Self {
    const state: State = if (current != target) .running else .finished;
    return Self{
        .current = current,
        .target = target,
        .step = step,
        .state = state,
    };
}

pub fn updateTarget(self: *Self, target: f64) void {
    self.target = target;
    self.state = .running;
}

pub fn nextStep(self: *Self) void {
    self.current += (self.target - self.current) * self.step;
}

// 是否接近完成
pub fn isNearFinished(self: *const Self) bool {
    return @abs(self.target - self.current) < FINISH_EPSILON;
}

pub fn finish(self: *Self) void {
    self.current = self.target;
    self.state = .finished;
}
