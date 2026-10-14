const sdl = @import("sdl");
const GPURenderPass = sdl.GPURenderPass;
const GPUCommandBuffer = sdl.GPUCommandBuffer;
const Event = @import("Event.zig");
const Self = @This();

pub const VTable = struct {
    draw: *const fn (*anyopaque, *GPUCommandBuffer, *GPURenderPass) void,
    event: *const fn (*anyopaque, *const Event) void,

    pub fn of(comptime T: type) *const VTable {
        const gen = struct {
            fn _draw(ctx: *anyopaque, cmd: *GPUCommandBuffer, pass: *GPURenderPass) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                return self.draw(cmd, pass);
            }

            fn _event(ctx: *anyopaque, e: *const Event) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                return self.event(e);
            }

            const vtable: VTable = .{ .draw = _draw, .event = _event }; // 前缀 `_` 避免歧义引用
        };

        return &gen.vtable;
    }
};

ptr: *anyopaque,
vtable: *const VTable,

pub fn draw(self: *const Self, cmd: *GPUCommandBuffer, pass: *GPURenderPass) void {
    self.vtable.draw(self.ptr, cmd, pass);
}

pub fn event(self: *Self, e: *const Event) void {
    self.vtable.event(self.ptr, e);
}
