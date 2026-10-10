const std = @import("std");
const Allocator = std.mem.Allocator;
const State = @import("State.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Gpu = @import("Gpu.zig");
const Preview = @import("Preview.zig");
const InstanceError = @import("errors.zig").Error;
const Self = @This();

pub const Error = InstanceError || Allocator.Error;
pub const Mode = enum { preview, gpu };

pub const VTable = struct {
    show: *const fn (*anyopaque) Error!ExitAction,
    destroy: *const fn (*anyopaque, Allocator) void,

    pub fn of(comptime T: type) *const VTable {
        const gen = struct {
            fn _show(ctx: *anyopaque) Error!ExitAction {
                const self: *T = @ptrCast(@alignCast(ctx));
                return self.show();
            }

            fn _destroy(ctx: *anyopaque, allocator: Allocator) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                self.deinit();
                allocator.destroy(self);
            }

            const vtable: VTable = .{ .show = _show, .destroy = _destroy }; // 前缀 `_` 避免歧义引用
        };

        return &gen.vtable;
    }
};

ptr: *anyopaque,
vtable: *const VTable,
allocator: Allocator,

pub fn create(allocator: Allocator, mode: Mode, external_state: *State) Error!Self {
    return switch (mode) {
        .gpu => return make(allocator, external_state, Gpu),
        .preview => return make(allocator, external_state, Preview),
    };
}

pub fn destroy(self: Self) void {
    self.vtable.destroy(self.ptr, self.allocator);
}

pub fn show(self: Self) Error!ExitAction {
    return self.vtable.show(self.ptr);
}

fn make(allocator: Allocator, external_state: *State, T: type) Error!Self {
    const ptr = try allocator.create(T); // 新增 Allocator.Error
    errdefer allocator.destroy(ptr);
    ptr.* = try T.init(allocator, external_state);

    return .{ .ptr = ptr, .vtable = VTable.of(T), .allocator = allocator };
}
