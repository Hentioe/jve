const sdl = @import("sdl");
const GPURenderPass = sdl.GPURenderPass;
const GPUCommandBuffer = sdl.GPUCommandBuffer;
const Self = @This();

pub const VTable = struct {
    draw: *const fn (*anyopaque, *GPUCommandBuffer, *GPURenderPass) void,

    pub fn of(comptime T: type) *const VTable {
        const gen = struct {
            fn _draw(ctx: *anyopaque, cmd: *GPUCommandBuffer, pass: *GPURenderPass) void {
                const self: *T = @ptrCast(@alignCast(ctx));
                return self.draw(cmd, pass);
            }

            const vtable: VTable = .{ .draw = _draw }; // 前缀 `_` 避免歧义引用
        };

        return &gen.vtable;
    }
};

ptr: *anyopaque,
vtable: *const VTable,

pub fn draw(self: *const Self, cmd: *GPUCommandBuffer, pass: *GPURenderPass) void {
    self.vtable.draw(self.ptr, cmd, pass);
}
