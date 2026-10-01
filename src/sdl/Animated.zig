const std = @import("std");
const c = @import("c.zig").c;
const Self = @This();

const FINISH_EPSILON = 0.001;
const State = enum { running, finished };

init_current: f64,
init_target: f64,
init_step: f64,
current: f64,
target: f64,
step: f64,
state: State,

pub fn init(current: f64, target: f64, step: f64) Self {
    const state: State = if (current != target) .running else .finished;
    return Self{
        .init_current = current,
        .init_target = target,
        .init_step = step,
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

pub fn nextStep(self: *Self, delta: f64) void {
    self.current += (self.target - self.current) * self.step * delta;
}

// 是否接近完成
pub fn isNearFinished(self: *const Self) bool {
    return @abs(self.target - self.current) < FINISH_EPSILON;
}

pub fn finish(self: *Self) void {
    self.current = self.target;
    self.state = .finished;
}

pub fn reset(self: *Self) void {
    self.current = self.init_current;
    self.target = self.init_target;
    self.step = self.init_step;
    self.state = if (self.current != self.target) .running else .finished;
}
