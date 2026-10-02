const c = @import("c.zig").c;
const Self = @This();

/// 上一帧到这一帧的时间间隔（秒），每次调用 update() 后刷新
value: f64 = 0,
/// 当前帧率估算（1 / dt）
fps: f64 = 0,

last_counter: u64,
freq: f64,

pub fn init() Self {
    return .{
        .last_counter = c.SDL_GetPerformanceCounter(),
        .freq = @floatFromInt(c.SDL_GetPerformanceFrequency()),
    };
}

/// 每帧循环开头调用一次
pub fn update(self: *Self) void {
    const now = c.SDL_GetPerformanceCounter();
    const ticks: f64 = @floatFromInt(now - self.last_counter); // 用整数先相减，避免大数转 f64 时丢失精度
    self.value = ticks / self.freq;
    self.fps = if (self.value > 0) 1.0 / self.value else 0;
    self.last_counter = now;
}

// 返回 f32 类型的 value
pub fn valueAsF32(self: *Self) f32 {
    return @floatCast(self.value);
}
