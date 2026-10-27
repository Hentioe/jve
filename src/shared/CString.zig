const std = @import("std");
const Allocator = std.mem.Allocator;
const Self = @This();

pub const Error = error{ PathTooLong, NameTooLong, StringTooLong } || Allocator.Error;

const PATH_MAX = std.fs.max_path_bytes + 1;
const NAME_MAX = std.fs.max_name_bytes + 1;
const SHORT_MAX = 255;

const Storage = union(enum) {
    short_buffer: [SHORT_MAX]u8,
    name_buffer: [NAME_MAX]u8,
    path_buffer: [PATH_MAX]u8,
    owned: [:0]u8,
};

len: usize,
storage: Storage,

pub fn from(allocator: Allocator, str: []const u8) Allocator.Error!Self {
    const inner = try allocator.dupeSentinel(u8, str, 0);
    return Self{ .len = inner.len, .storage = .{ .owned = inner } };
}

pub fn fromOwned(allocator: Allocator, str: []u8) Allocator.Error!Self {
    defer allocator.free(str);
    return from(allocator, str);
}

pub fn fromShort(str: []const u8) Error!Self {
    const len = str.len;
    if (len > SHORT_MAX) return Error.StringTooLong;
    var storage: Storage = .{ .short_buffer = undefined };
    @memcpy(storage.short_buffer[0..len], str);
    storage.short_buffer[len] = 0;

    return Self{ .len = len, .storage = storage };
}

pub fn fromName(name: []const u8) Error!Self {
    const len = name.len;
    if (len > NAME_MAX) return Error.NameTooLong;
    var storage: Storage = .{ .name_buffer = undefined };
    @memcpy(storage.name_buffer[0..len], name);
    storage.name_buffer[len] = 0;

    return Self{ .len = len, .storage = storage };
}

pub fn fromPath(path: []const u8) Error!Self {
    const len = path.len;
    if (len > PATH_MAX) return Error.PathTooLong;
    var storage: Storage = .{ .path_buffer = undefined };
    @memcpy(storage.path_buffer[0..len], path);
    storage.path_buffer[len] = 0;

    return Self{ .len = len, .storage = storage };
}

pub fn data(self: *const Self) [:0]const u8 {
    switch (self.storage) {
        .short_buffer => |*buf| return buf[0..self.len :0],
        .name_buffer => |*buf| return buf[0..self.len :0],
        .path_buffer => |*buf| return buf[0..self.len :0],
        .owned => |val| return val,
    }
}

pub fn deinit(self: *Self, allocator: Allocator) void {
    switch (self.storage) {
        .owned => |val| allocator.free(val),
        else => {},
    }
    self.* = undefined;
}

pub fn format(self: *const Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    try writer.print("{s}", .{self.data()});
}
