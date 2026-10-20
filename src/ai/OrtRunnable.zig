const std = @import("std");
const ort = @import("ort");
const Allocator = std.mem.Allocator;
const Api = ort.Api;
const Image = @import("vips").Image;
const Input = @import("processors/Input.zig");
const BiRefNet = @import("runners/BiRefNet.zig");
const MagicTouch = @import("runners/MagicTouch.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

pub const Model = enum { birefnet, magic_touch };
pub const VTable = struct {
    run: *const fn (*const anyopaque, input: Input) Error!Image,
    destroy: *const fn (*anyopaque, Allocator) void,

    pub fn of(comptime T: type) VTable {
        const gen = struct {
            fn run(ctx: *const anyopaque, input: Input) Error!Image {
                const self: *const T = @ptrCast(@alignCast(ctx));
                return self.run(input);
            }

            fn destroy(ctx: *anyopaque, allocator: Allocator) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                self.deinit();
                allocator.destroy(self);
            }
        };
        return .{ .run = gen.run, .destroy = gen.destroy };
    }
};

ptr: *anyopaque,
vtable: *const VTable,
allocator: Allocator,

pub fn create(model: Model, api: *const Api) Error!Self {
    return switch (model) {
        .birefnet => make(api.gpa, try BiRefNet.init(api)),
        .magic_touch => make(api.gpa, try MagicTouch.init(api)),
    };
}

pub fn run(self: *Self, input: Input) Error!Image {
    return self.vtable.run(self.ptr, input);
}

pub fn destroy(self: *Self) void {
    self.vtable.destroy(self.ptr, self.allocator);
}

fn make(allocator: Allocator, impl: anytype) Error!Self {
    const T = @TypeOf(impl);
    const ptr = try allocator.create(T);
    ptr.* = impl;

    return .{ .allocator = allocator, .ptr = ptr, .vtable = &T.vtable };
}
