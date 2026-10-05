const std = @import("std");
const Instant = std.time.Instant;
const Error = @import("errors.zig").TimerError;
const Self = @This();

/// 时间单位
pub const Unit = enum { ns, ms, s };

/// 开始时间
started: Instant,
/// 最近一次计时的结果（纳秒）；null 表示还没有结果
result_ns: ?u64 = null,

/// 开始计时。重复调用会重置起点，并清空上一次的结果。
pub fn start() Error!Self {
    return .{ .started = try now() };
}

/// 结束计时，更新 result_ns 并返回耗时（指定单位）。
pub fn finish(self: *Self, unit: Unit) Error!f64 {
    const elapsed = (try now()).since(self.started);
    self.result_ns = elapsed;
    return self.result(unit).?;
}

/// 是否正在计时
pub fn isRunning(self: Self) bool {
    return self.started != null;
}

/// 以指定单位读取计时结果
pub fn result(self: Self, unit: Unit) ?f64 {
    const ns = self.result_ns orelse return null;
    const value: f64 = switch (unit) {
        .ns => @as(f64, @floatFromInt(ns)),
        .ms => @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms,
        .s => @as(f64, @floatFromInt(ns)) / std.time.ns_per_s,
    };
    return roundTo2(value);
}

pub fn now() Error!Instant {
    return Instant.now() catch return Error.TimerUnsupported;
}

fn roundTo2(x: f64) f64 {
    return @round(x * 100.0) / 100.0;
}
