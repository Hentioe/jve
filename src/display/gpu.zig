const std = @import("std");
const Allocator = std.mem.Allocator;
const Gpu = @import("Gpu.zig");
const State = @import("State.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;

// 基于 SDL_GPU 渲染图片
pub fn render(allocator: Allocator, state: *State) Error!ExitAction {
    // 惰性创建 Gpu（窗口、设备、着色器资源在模式切换间复用）
    if (state.gpu == null) {
        state.gpu = try Gpu.init(allocator, state);
    }
    if (state.gpu) |*gpu| {
        return try gpu.show();
    }
    unreachable;
}
