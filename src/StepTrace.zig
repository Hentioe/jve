const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Self = @This();

pub const Error = Allocator.Error;

pub const Mark = struct {
    name: []const u8,
    ns: u64,
};

const io = std.Io.Threaded.global_single_threaded.io();

allocator: Allocator,
name: []const u8,
start: Io.Timestamp,
marks: std.ArrayList(Mark) = .empty,
completed: bool = false,

pub fn init(allocator: Allocator, name: []const u8) Self {
    return .{
        .allocator = allocator,
        .name = name,
        .start = Io.Clock.awake.now(io),
    };
}

pub fn deinit(self: *Self) void {
    self.marks.deinit(self.allocator);
    self.* = undefined;
}

/// 从 init 到现在经过的纳秒数
fn elapsedNs(self: *const Self) u64 {
    const d = self.start.untilNow(io, .awake);
    return @intCast(d.toNanoseconds());
}

/// 打点
pub fn mark(self: *Self, name: []const u8) Error!void {
    if (self.completed) return;
    try self.marks.append(self.allocator, .{
        .name = name,
        .ns = self.elapsedNs(),
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
    std.log.info("Step tracking complete (total {d:.0}ms)", .{toMs(self.elapsedNs())});
    self.completed = true;
}

fn toMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}
