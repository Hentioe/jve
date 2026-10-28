const std = @import("std");
const shared = @import("shared");
const CString = shared.CString;
const Io = std.Io;
const Threaded = Io.Threaded;

pub const PollHandler = @import("tasks/PollHandler.zig");

pub const CustomError = error{FutureNotFound};
pub const ConcurrencyError = error{ConcurrencyUnavailable};
pub const QueueGetError = error{ Canceled, Closed };
pub const PollError = error{OutOfMemory};
pub const Error = CustomError || ConcurrencyError || QueueGetError || PollError;

pub const Name = enum { save_screenshot, copy_screenshot };
pub const NameSet = std.EnumSet(Name);
pub const Result = union(enum) {
    cstr: CString,
    ok: void,
    err: anyerror,
};
pub const Elem = struct { name: Name, result: Result };

const LaunchableTasks = struct {
    pub const screenshot = @import("tasks/screenshot.zig");
};

pub const LaunchArgs = union(enum) {
    screenshot: DropPrefix(LaunchableTasks.screenshot.args),

    fn fieldTypes(comptime T: type) [@typeInfo(T).@"struct".field_types.len]type {
        const field_types = @typeInfo(T).@"struct".field_types;
        var types: [field_types.len]type = undefined;
        for (field_types, 0..) |t, i| types[i] = t;
        return types;
    }

    fn assemble(comptime Full: type, prefix: anytype, rest: anytype) Full {
        var full: Full = undefined;
        inline for (0..prefix.len) |i| full[i] = prefix[i];
        inline for (0..rest.len) |i| full[prefix.len + i] = rest[i];
        return full;
    }

    fn DropPrefix(comptime T: type) type {
        const types = fieldTypes(T);
        return @Tuple(types[2..]);
    }
};

pub const Scheduler = struct {
    const Self = @This();

    var done_buffer: [NameSet.len]Name = undefined;
    var results_buffer: [NameSet.len]Elem = undefined;

    io: Io,
    jobs: [NameSet.len]?Io.Future(Result) = @splat(null),
    done: Io.Queue(Name) = .init(&done_buffer),

    pub fn init(threaded: *Threaded) Self {
        return Self{ .io = threaded.io() };
    }

    pub fn deinit(self: *Self) void {
        for (&self.jobs) |*slot| if (slot.*) |*future| {
            _ = future.cancel(self.io); // 销毁 future
        };
        self.done.close(self.io);
    }

    pub fn launch(self: *Self, name: Name, args: LaunchArgs) ConcurrencyError!void {
        const idx = @backingInt(name);
        if (self.jobs[idx] != null) return;
        switch (args) {
            inline else => |tuple, tag| {
                const task = @field(LaunchableTasks, @tagName(tag));
                const full = LaunchArgs.assemble(task.args, .{ self, name }, tuple);
                self.jobs[idx] = try self.io.concurrent(task.launch, full);
            },
        }
    }

    pub fn poll(self: *Self) Error![]Elem {
        var out: [NameSet.len]Name = undefined;
        const count = try self.done.getUncancelable(self.io, &out, 0);
        if (count == 0) return &.{};
        var results: std.ArrayList(Elem) = .initBuffer(&results_buffer);
        for (out[0..count]) |name| {
            const idx = @backingInt(name);
            if (self.jobs[idx]) |*future| { // 回收 future 并重置槽位
                const result = future.await(self.io);
                self.jobs[idx] = null;
                try results.appendBounded(.{ .name = name, .result = result });
            } else {
                return Error.FutureNotFound;
            }
        }
        return results.items;
    }

    pub fn buildDone(self: *Self, name: Name, result: Result) Result {
        self.done.putOne(self.io, name) catch |err| {
            std.log.err("Failed to put done element in queue: {}", .{err});
        };

        return result;
    }
};
