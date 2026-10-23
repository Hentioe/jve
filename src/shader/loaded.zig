const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const Items = std.ArrayList(Item);
const BorrowedItems = std.ArrayList(*const Item);
const Keybinding = @import("../config.zig").Keybinding;
const Error = @import("errors.zig").Error;

// 激活方式字段（手动、默认）
pub const Activation = enum { manual, default };

pub const Item = struct {
    shader: *sdl.GPUShader,
    activation: Activation,
    keybinding: ?Keybinding = null,
};

pub const All = struct {
    gpa: Allocator,
    list: Items,
    manuals_num: u32 = 0,
    defaults_num: u32 = 0,

    pub fn init(allocator: Allocator) Error!All {
        return All{
            .gpa = allocator,
            .list = .empty,
        };
    }

    pub fn deinit(self: *All) void {
        self.list.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn add(self: *All, item: Item) Error!void {
        try self.list.append(self.gpa, item);
        if (item.activation == Activation.manual) {
            self.manuals_num += 1;
        } else if (item.activation == Activation.default) {
            self.defaults_num += 1;
        }
    }

    pub fn manuals(self: *const All, allocator: Allocator) Error!BorrowedItems {
        var result: BorrowedItems = try .initCapacity(allocator, self.manuals_num);
        for (self.list.items) |*item| {
            if (item.activation == Activation.manual) {
                try result.append(allocator, item);
            }
        }
        return result;
    }

    pub fn defaults(self: *const All, allocator: Allocator) Error!BorrowedItems {
        var result: BorrowedItems = try .initCapacity(allocator, self.defaults_num);
        for (self.list.items) |*item| {
            if (item.activation == Activation.default) {
                try result.append(allocator, item);
            }
        }
        return result;
    }
};
