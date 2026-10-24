const std = @import("std");
const Allocator = std.mem.Allocator;
const Timer = std.time.Timer;
const Self = @This();

pub const Error = std.time.Timer.Error || Allocator.Error;

pub const Mark = struct {
    name: []const u8,
    ns: u64,
};

allocator: Allocator,
name: []const u8,
timer: Timer,
marks: std.ArrayList(Mark) = .empty,
completed: bool = false,

/// 初始化跟踪器，如果 `std.time.Timer` 不可用将直接崩溃。
pub fn init(allocator: Allocator, name: []const u8) Self {
    return .{
        .allocator = allocator,
        .name = name,
        .timer = Timer.start() catch @panic("monotonic clock unavailable"),
    };
}

/// 安全版 init，返回 Error 而不是崩溃。
pub fn initSafe(allocator: Allocator, name: []const u8) Error!Self {
    return .{
        .allocator = allocator,
        .name = name,
        .timer = try Timer.start(),
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
    std.debug.print("Step tracking report for: {s}\n", .{self.name});
    std.debug.print(" {s:<16} {s:>12} {s:>12}\n", .{ "stage", "delta(ms)", "total(ms)" });
    var prev: u64 = 0;
    for (self.marks.items) |m| {
        const delta_ms = toMs(m.ns - prev);
        const total_ms = toMs(m.ns);
        std.debug.print(" {s:<16} {d:>12.3} {d:>12.3}\n", .{ m.name, delta_ms, total_ms });
        prev = m.ns;
    }
}

/// 标记跟踪器已完成，并输出总耗时。
pub fn complete(self: *Self) void {
    std.log.info("Step tracking complete (total {d:.0}ms)", .{toMs(self.timer.read())});
    self.completed = true;
}

fn toMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}
