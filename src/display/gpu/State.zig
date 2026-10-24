const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("../../config.zig");
const pipelines = @import("../../pipelines.zig");
const Point = shared.Point(f32);
const Delta = @import("../Delta.zig");
const Modifiers = @import("../Modifiers.zig");
const ModKey = @import("../ModKey.zig");
const OverflowHint = @import("../OverflowHint.zig");
const Playback = @import("../Playback.zig");
const Task = @import("../Task.zig");
const RenderDeps = @import("RenderDeps.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

/// 截图输入状态
pub const ScreenshotInput = struct {
    pub const Action = enum { save, copy, none };

    action: Action = .none, // 截图动作
    include_bg: bool = false, // 是否包含背景

    pub const default: ScreenshotInput = .{};
};

/// 标记半径（像素），同时作为二次点击移除的判定范围
pub const MARKER_RADIUS: f32 = 18.0;

running: bool = true,
delta: *const Delta,
toggle: bool = false,
dirty: bool = false,
// 动图播放状态（静态图时 playing 为 false，不参与渲染循环）
playback: Playback,
// 修饰键
modifiers: Modifiers,
mod_key: ModKey,
// 其它开关
custom_shader_enabled: bool = false,
// 基础着色器控制变量
is_inverted: bool = false, // 是否反转颜色
is_grayscale: bool = false, // 是否灰阶化
brightness: f32 = 0, // 亮度调整值（暂未实现）
contrast: f32 = 1, // 对比度调整值（暂未实现）
gamma: f32 = 1, // Gamma 校正值（暂未实现）
channel: i32 = 0, // 0: 正常全彩, 1: R, 2: G, 3: B, 4: A
// 截图输入
screenshot: ScreenshotInput = .default,
// 是否正在繁忙处理
is_busy: bool = false,
// 横向滑动控制变量
is_sliding: bool = false,
slide_value: f32 = 0,
// 标记
marker_pos: ?Point = null,
// 任务（后台调用模型）
task: ?*Task = null,
tex_mask: ?*sdl.GPUTexture = null,
// 超出提示动画（图片过大被限制尺寸时，屏幕边缘显示提示）
overflow_hint: OverflowHint,
// 乒乓纹理
tex_src: *sdl.GPUTexture,
tex_dst: *sdl.GPUTexture,
// 手动触发的管线
manual: ?*pipelines.Post = null,
// 是否显示错误
show_error: bool = false,

pub fn init(deps: *const RenderDeps, delta: *const Delta) Self {
    var state = Self{
        .delta = delta,
        .modifiers = Modifiers.init(),
        .mod_key = ModKey.init(config.get().mod_key),
        .overflow_hint = OverflowHint.init(1.25, 1.25, 0.9),
        .playback = Playback.init(sdl.getTicks(), deps.animation != null),
        .tex_src = deps.tex_a,
        .tex_dst = deps.tex_b,
    };
    if (deps.window.overflow != .none) state.overflow_hint.trigger();
    return state;
}

pub fn deinit(self: *Self) void {
    self.* = undefined;
}

pub fn showError(self: *Self, deps: *RenderDeps, comptime fmt: []const u8, args: anytype) Error!void {
    const message = try std.fmt.allocPrint(deps.allocator, fmt, args);
    defer deps.allocator.free(message);
    try deps.error_banner.setText(message);
    self.show_error = true;
}
