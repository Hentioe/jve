const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config");
const Delta = @import("../Delta.zig");
const ModKey = @import("../ModKey.zig");
const OverflowHint = @import("../OverflowHint.zig");
const Task = @import("../Task.zig");
const RenderDeps = @import("RenderDeps.zig");
const display_state = @import("../State.zig");
const Point = shared.Point(f32);
const Self = @This();

/// 标记半径（像素），同时作为二次点击移除的判定范围
pub const marker_radius: f32 = 18.0;

external_state: *display_state, // 外部状态

running: bool = true,
delta: *const Delta,
toggle: bool = false,
dirty: bool = false,
// 其它开关
mod_key: ModKey,
custom_shader_enabled: bool = false,
// 基础着色器控制变量
is_inverted: bool = false, // 是否反转颜色
is_grayscale: bool = false, // 是否灰阶化
brightness: f32 = 0, // 亮度调整值（暂未实现）
contrast: f32 = 1, // 对比度调整值（暂未实现）
gamma: f32 = 1, // Gamma 校正值（暂未实现）
channel: i32 = 0, // 0: 正常全彩, 1: R, 2: G, 3: B, 4: A
// 截图
save_screenshot: bool = false,
copy_screenshot: bool = false,
// 是否正在繁忙处理
is_busy: bool = false,
// 横向滑动控制变量
is_sliding: bool = false,
slide_value: f32 = 0,
// 标记
marker_pos: ?Point = null,
// 任务（后台调用模型）
task: ?*Task = null,
tex_mask: ?*sdl.c.SDL_GPUTexture = null,
// 超出提示动画（图片过大被限制尺寸时，屏幕边缘显示提示）
overflow_hint: OverflowHint,
// 乒乓纹理
tex_src: *sdl.c.SDL_GPUTexture,
tex_dst: *sdl.c.SDL_GPUTexture,

pub fn init(deps: *const RenderDeps, delta: *const Delta) Self {
    var state = Self{
        .external_state = deps.external_state,
        .delta = delta,
        .mod_key = ModKey.init(ModKey.keycode(config.modKey())),
        .overflow_hint = OverflowHint.init(1.25, 1.25, 0.9),
        .tex_src = deps.tex_a,
        .tex_dst = deps.tex_b,
    };
    if (deps.window.overflow != .none) state.overflow_hint.trigger();
    return state;
}
