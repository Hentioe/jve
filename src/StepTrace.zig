const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const Self = @This();

pub const Error = Allocator.Error;

pub const Mark = struct {
    name: []const u8,
    ns: u64,
};

allocator: Allocator,
timer: Timer,
marks: std.ArrayList(Mark) = .empty,
completed: bool = false,

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .timer = Timer.start() catch @panic("monotonic clock unavailable"),
    };
}

pub fn deinit(self: *Self) void {
    self.marks.deinit(self.allocator);
    self.* = undefined;
}

/// 打点
pub fn mark(self: *Self, name: []const u8) Error!void {
    if (self.completed) return;
    try self.marks.append(self.allocator, Mark{
        .name = name,
        .ns = self.timer.read(),
    });
}

/// 统一输出
pub fn report(self: *const Self) void {
    std.debug.print("{s:<16} {s:>12} {s:>12}\n", .{ "stage", "delta(ms)", "total(ms)" });
    var prev: u64 = 0;
    for (self.marks.items) |m| {
        const delta_ms = toMs(m.ns - prev);
        const total_ms = toMs(m.ns);
        std.debug.print("{s:<16} {d:>12.3} {d:>12.3}\n", .{ m.name, delta_ms, total_ms });
        prev = m.ns;
    }
}

/// 标记 StepTrace 已完成
pub fn complete(self: *Self) void {
    std.log.info("StepTrace completed", .{});
    self.completed = true;
}

fn toMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}
