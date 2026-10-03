const Self = @This();

const FINISH_EPSILON = 0.001;
const State = enum { running, finished };

// 将状态拆分为初始值和目标值，通过累积步长逐步逼近目标以在渲染循环中实现动画。用法例子：
// var scale = Animated.init(1.0, 2.0, 15); // 包装「缩放」状态
// white(running) {
//     // ...
//     scale.nextStep(delta.value); // 在循环中不断步进
//     const new_width = width * scale.current; // 计算当前的新宽度
//     const new_height = height * scale.current; // 计算当前的新高度
// }

// 存储初始化的值（用于重置）
const Initial = struct {
    current: f64,
    target: f64,
    step: f64,
};

initial: Initial,
current: f64,
target: f64,
step: f64,
state: State,

pub fn init(current: f64, target: f64, step: f64) Self {
    const state: State = if (current != target) .running else .finished;
    return Self{
        .initial = Initial{
            .current = current,
            .target = target,
            .step = step,
        },
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
    self.current = self.initial.current;
    self.target = self.initial.target;
    self.step = self.initial.step;
    self.state = if (self.current != self.target) .running else .finished;
}
