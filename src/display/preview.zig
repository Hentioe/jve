const std = @import("std");
const Allocator = std.mem.Allocator;
const Preview = @import("Preview.zig");
const State = @import("State.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;

// 基于 sdl_renderer 渲染图片
pub fn render(allocator: Allocator, state: *State) Error!ExitAction {
    // 惰性创建 Preview（窗口、渲染器资源在模式切换间复用）
    if (state.preview == null) {
        state.preview = try Preview.init(allocator, state);
    }
    if (state.preview) |*preview| {
        return try preview.show();
    }
    unreachable;
}
