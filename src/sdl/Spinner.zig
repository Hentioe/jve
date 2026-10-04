// 目前此组件并未实际使用。实验阶段已证实可用性，但它不适合图片切换动画（已由 SlideIn 取代）。

const std = @import("std");
const Self = @This();

/// 收尾时与目标的最大误差（度），小于该值即视为归位。
const SETTLE_EPSILON = 0.5;

pub const State = enum { spinning, settling, stopped };

/// 一圈的大小。角度用度数就是 360，用弧度就是 2π。
period: f64,
/// 循环阶段的速度（单位/秒）。
speed: f64,
/// 收尾阶段的收敛系数（与 Animated.step 含义相同）。
settle_step: f64,

current: f64 = 0,
target: f64 = 0,
state: State = .stopped,

pub fn init(period: f64, speed: f64, settle_step: f64) Self {
    return .{
        .period = period,
        .speed = speed,
        .settle_step = settle_step,
    };
}

/// 复位到初始角度并停止（不经过收尾）。
pub fn reset(self: *Self) void {
    self.current = 0;
    self.target = 0;
    self.state = .stopped;
}

/// 开始（或重新开始）循环旋转。
/// 若正在收尾，则从当前角度无缝接着转，不会跳变。
pub fn start(self: *Self) void {
    self.state = .spinning;
}

/// 请求停止：此刻才动态确定目标——沿当前转向前方最近的整圈位置。
pub fn stop(self: *Self) void {
    if (self.state != .spinning) return;
    // 沿转向方向找最近的 period 整数倍
    const turns = if (self.speed >= 0)
        @ceil(self.current / self.period)
    else
        @floor(self.current / self.period);
    self.target = turns * self.period;
    self.state = .settling;
}

pub fn nextStep(self: *Self, delta: f64) void {
    switch (self.state) {
        .spinning => {
            self.current += self.speed * delta;
        },
        .settling => {
            const dist = self.target - self.current;
            // 指数逼近目标；大 delta 时 k 取 1.0，避免超调
            const k = @min(self.settle_step * delta, 1.0);
            self.current += dist * k;

            if (@abs(self.target - self.current) < SETTLE_EPSILON) {
                self.current = 0;
                self.target = 0;
                self.state = .stopped;
            }
        },
        .stopped => {},
    }
}

pub fn isStopped(self: *const Self) bool {
    return self.state == .stopped;
}

pub fn isSpinning(self: *const Self) bool {
    return self.state == .spinning;
}
