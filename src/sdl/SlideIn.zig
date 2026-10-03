const Self = @This();

pub const State = enum { idle, running };

/// 旋转的整圈数。
turns: f64,
/// 滑入的收敛系数（与 Animated.step 含义相同）。
step: f64,
/// 位移小于该像素值即视为抵达屏幕中心。
center_epsilon: f64,

/// 滑入的起始偏移（带符号，决定滑入方向）。
start_pos: f64 = 0,
/// 当前水平偏移。
offset: f64 = 0,
/// 当前旋转角度（度数）。
angle: f64 = 0,
state: State = .idle,

pub fn init(turns: f64, step: f64, center_epsilon: f64) Self {
    return .{
        .turns = turns,
        .step = step,
        .center_epsilon = center_epsilon,
    };
}

/// 从 start_pos（带符号的屏幕外偏移）滑入到 0：负值自左侧，正值自右侧。
pub fn start(self: *Self, start_pos: f64) void {
    self.start_pos = start_pos;
    self.offset = start_pos;
    self.angle = 0;
    self.state = .running;
}

/// 依据窗口与图片宽度，从对应边缘的外侧开始滑入。
/// to_next 为真时自左侧（顺时针），否则自右侧（逆时针）。
pub fn startFromEdge(self: *Self, window_width: f64, image_width: f64, to_next: bool) void {
    const half_span = (window_width + image_width) / 2.0;
    self.start(if (to_next) -half_span else half_span);
}

/// 指数逼近中心，旋转角度由滑入进度决定：进度 0→1 映射到整圈，
/// 抵达中心时正好转满，因此不存在收尾零头。
pub fn nextStep(self: *Self, delta: f64) void {
    if (self.state != .running) return;

    const prev = self.offset;
    self.offset += (0 - self.offset) * self.step * delta;

    // 足够接近中心，或大 delta 导致越过中心：直接归位。
    if (@abs(self.offset) < self.center_epsilon or self.offset * prev < 0) {
        self.offset = 0;
        self.angle = 0;
        self.state = .idle;
        return;
    }

    const progress = 1.0 - @abs(self.offset) / @abs(self.start_pos);
    const dir: f64 = if (self.start_pos < 0) 1.0 else -1.0; // 左滑顺时针，右滑逆时针
    self.angle = dir * self.turns * 360.0 * progress;
}

pub fn isRunning(self: *const Self) bool {
    return self.state == .running;
}
