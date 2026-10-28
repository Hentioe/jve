const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const CString = shared.CString;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Results = std.ArrayList(Elem);
const Screenshot = @import("../../Screenshot.zig");
const vips = @import("vips");
const LImage = vips.LImage;
const Self = @This();

pub const ConcurrencyError = error{ConcurrencyUnavailable};
pub const QueueGetError = error{ Canceled, Closed };
pub const PollError = error{OutOfMemory};
pub const Error = ConcurrencyError || QueueGetError || PollError;

const Name = enum { save_screenshot, copy_screenshot };
const NameSet = std.EnumSet(Name);
const Result = union(enum) {
    cstr: CString,
    ok: bool,
    fail: anyerror,
};
const Elem = struct { name: Name, result: Result };

var queue_buffer: [NameSet.len]Elem = undefined;
var results_buffer: [NameSet.len]Elem = undefined;

io: Io,
queue: Io.Queue(Elem) = .init(&queue_buffer),
futures: [NameSet.len]?Io.Future(void) = @splat(null),

pub fn init(io: Io) Self {
    return Self{ .io = io };
}

pub fn deinit(self: *Self) void {
    for (&self.futures) |*slot| if (slot.*) |*future| {
        _ = future.cancel(self.io); // 销毁 future
    };
    self.queue.close(self.io);
}

pub fn poll(self: *Self) Error![]Elem {
    var out: [NameSet.len]Elem = undefined;
    const count = try self.queue.getUncancelable(self.io, &out, 0);
    if (count == 0) return &.{};
    var results: Results = .initBuffer(&results_buffer);
    for (out[0..count]) |e| {
        const idx = @backingInt(e.name);
        // 回收 future 并重置槽位
        if (self.futures[idx]) |*future| {
            _ = future.await(self.io);
            self.futures[idx] = null;
        }
        try results.appendBounded(e);
    }
    return results.items;
}

pub fn put(self: *Self, name: Name, result: Result) void {
    self.queue.putOne(self.io, Elem{ .name = name, .result = result }) catch |err| {
        std.log.err("Failed to put element in queue: {}", .{err});
    };
}

pub fn laucnhScreenshot(
    self: *Self,
    allocator: Allocator,
    gpu_dvice: *const sdl.Gpu,
    tex: *sdl.GPUTexture,
    image: *LImage,
    action: Screenshot.Action,
) ConcurrencyError!void {
    const name: Name = if (action == .save) .save_screenshot else .copy_screenshot;
    const idx = @backingInt(name);
    if (self.futures[idx] != null) return;
    self.futures[idx] = try self.io.concurrent(screenshot, .{ self, allocator, gpu_dvice, tex, image, name });
}

fn screenshot(
    self: *Self,
    allocator: Allocator,
    gpu_dvice: *const sdl.Gpu,
    tex: *sdl.GPUTexture,
    image: *LImage,
    name: Name,
) void {
    var s = Screenshot.init(allocator, gpu_dvice, tex, image) catch |err| {
        self.put(name, .{ .fail = err });
        return;
    };

    defer s.deinit();
    if (name == .save_screenshot) if (s.saveToFile()) |saved| {
        self.put(name, .{ .cstr = saved.filepath });
    } else |err| {
        self.put(name, .{ .fail = err });
    };
    if (name == .copy_screenshot) if (s.copyToClipboard()) {
        self.put(name, .{ .ok = false });
    } else |err| {
        self.put(name, .{ .fail = err });
    };
}
