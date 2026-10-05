const ort = @import("ort");
const Api = ort.Api;
const Error = @import("errors.zig").Error;
const Image = @import("../vips.zig").Image;
const Input = @import("processors/Input.zig");
const BiRefNet = @import("runners/BiRefNet.zig");
const MagicTouch = @import("runners/MagicTouch.zig");
const Self = @This();

pub const Model = enum { birefnet, magic_touch };
pub const VTable = struct {
    run: *const fn (*const anyopaque, input: Input) Error!Image,
    deinit: *const fn (*anyopaque) void,

    pub fn of(comptime T: type) VTable {
        const gen = struct {
            fn run(ctx: *const anyopaque, input: Input) Error!Image {
                const self: *const T = @ptrCast(@alignCast(ctx));
                return self.run(input);
            }
            fn deinit(ctx: *anyopaque) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                self.deinit();
            }
        };
        return .{ .run = gen.run, .deinit = gen.deinit };
    }
};

ptr: *anyopaque,
vtable: *const VTable,

pub fn init(model: Model, api: *const Api) Error!Self {
    return switch (model) {
        .birefnet => make(try BiRefNet.init(api)),
        .magic_touch => make(try MagicTouch.init(api)),
    };
}

pub fn run(self: *Self, input: Input) Error!Image {
    return self.vtable.run(self.ptr, input);
}

pub fn deinit(self: *Self) void {
    self.vtable.deinit(self.ptr);
}

fn make(impl: anytype) Self {
    const T = @typeInfo(@TypeOf(impl)).pointer.child;
    return .{ .ptr = impl, .vtable = &T.vtable };
}
