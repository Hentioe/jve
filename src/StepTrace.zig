const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Marks = std.ArrayList(Mark);
const Self = @This();

pub const Error = Allocator.Error;

pub const Mark = struct {
    name: []const u8,
    ns: u64,
};

const Storage = union(enum) {
    _alloc: struct { Allocator, Marks },
    _buffer: Marks,

    // 整个程序共享的池子，即 buffer 的总容量
    const pool_capacity = 1024;
    var pool: [pool_capacity]Mark = undefined;
    var pool_used: usize = 0;

    pub fn alloc(allocator: Allocator) Allocator.Error!Storage {
        return .{ ._alloc = .{ allocator, try Marks.initCapacity(allocator, 0) } };
    }

    pub fn buffer(size: usize) error{PoolCapacityExceeded}!Storage {
        if (size > pool_capacity - pool_used) return error.PoolCapacityExceeded;
        const b = pool[pool_used..][0..size];
        pool_used += size;
        return .{ ._buffer = Marks.initBuffer(b) };
    }
};
const io = std.Io.Threaded.global_single_threaded.io();

allocated: bool,
allocator: Allocator,
buffer: []Mark = undefined,
name: []const u8,
start: Io.Timestamp,
marks: Marks,
completed: bool = false,

pub fn init(storage: Storage, name: []const u8) Self {
    var marks: Marks = undefined;
    var allocator: Allocator = undefined;
    var allocated = false;
    switch (storage) {
        ._alloc => |tuple| {
            allocated = true;
            allocator = tuple.@"0";
            marks = tuple.@"1";
        },
        ._buffer => |m| {
            marks = m;
        },
    }
    return .{
        .allocated = allocated,
        .allocator = allocator,
        .marks = marks,
        .name = name,
        .start = Io.Clock.awake.now(io),
    };
}

pub fn deinit(self: *Self) void {
    if (self.allocated) self.marks.deinit(self.allocator);
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

/// 打点（有边界的）
pub fn markBounded(self: *Self, name: []const u8) void {
    if (self.completed) return;
    self.marks.appendBounded(.{
        .name = name,
        .ns = self.elapsedNs(),
    }) catch {
        std.log.warn("Step-tracking buffer is full: {s} ({s})", .{ name, self.name });
    };
}

/// 统一输出
pub fn report(self: *const Self) void {
    std.debug.print("Step-tracking report for: {s}\n", .{self.name});
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
    std.log.info("Step-tracking complete: {s} (total {d:.0}ms)", .{ self.name, toMs(self.elapsedNs()) });
    self.completed = true;
}

fn toMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / std.time.ns_per_ms;
}
