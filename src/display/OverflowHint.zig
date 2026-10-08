/// 定时提示动画：触发后在指定时长内显示，末尾淡出。
/// 用于图片过大被限制尺寸时，在屏幕边缘显示提示。
const Self = @This();

pub const State = enum { idle, running };

/// 提示总时长（秒）
duration: f64,
/// 末尾淡出时长（秒）
fade: f64,
/// 最大透明度
alpha_max: f32,

/// 已流逝的时间（秒）
elapsed: f64 = 0,
/// 当前透明度
alpha: f32 = 0,
state: State = .idle,

pub fn init(duration: f64, fade: f64, alpha_max: f32) Self {
    return .{
        .duration = duration,
        .fade = fade,
        .alpha_max = alpha_max,
    };
}

/// 重新开始提示动画。
pub fn trigger(self: *Self) void {
    self.elapsed = 0;
    self.alpha = self.alpha_max;
    self.state = .running;
}

/// 依据帧间隔推进动画。
pub fn nextStep(self: *Self, delta: f64) void {
    if (self.state != .running) return;

    self.elapsed += delta;
    if (self.elapsed >= self.duration) {
        self.elapsed = self.duration;
        self.alpha = 0;
        self.state = .idle;
        return;
    }

    const remaining = self.duration - self.elapsed;
    self.alpha = self.alpha_max * @as(f32, @floatCast(@min(1.0, remaining / self.fade)));
}

pub fn isRunning(self: *const Self) bool {
    return self.state == .running;
}
