const Self = @This();

// 剩余时间（毫秒）
remaining: f64,
// 已开始
started: bool,

pub fn init(remaining: f64) Self {
    const started = remaining > 0;
    return Self{
        .remaining = remaining,
        .started = started,
    };
}

pub fn start(self: *Self, duration: f64) void {
    self.remaining = duration;
    self.started = true;
}

pub fn tick(self: *Self, delta: f64) bool {
    if (!self.started) return false;
    if (self.remaining > delta) {
        self.remaining -= delta;
    } else {
        self.remaining = 0;
    }
    // 更新启动状态
    if (self.remaining <= 0) self.started = false;
    return true;
}
