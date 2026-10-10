const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config");
const Delta = @import("../Delta.zig");
const ModKey = @import("../ModKey.zig");
const Animated = @import("../Animated.zig");
const SlideIn = @import("../SlideIn.zig");
const Window = @import("../window.zig");
const RenderDeps = @import("RenderDeps.zig");
const app_env = @import("../../app_env.zig");
const Size2D = shared.Size2D;
const Point = shared.Point(f32);
const Self = @This();

running: bool = true,
delta: *const Delta,
dst_rect: sdl.c.SDL_FRect = .{},
mod_key: ModKey,
is_dragging: bool = false,
move_offset: Point,
scale: Animated,
angle: Animated,
slide: SlideIn,
toggle: bool = false,
dirty: bool = true,

pub fn init(deps: *const RenderDeps, delta: *const Delta) Self {
    const env = app_env.reader();
    // 缩放/角度从全局缓存的目标值开始
    var scale = Animated.init(1.0, 1.0, 15);
    scale.updateTarget(env.target_scale);
    var angle = Animated.init(0.0, 0.0, 15);
    angle.updateTargetAngular(env.target_angle);
    var state = Self{
        .delta = delta,
        .mod_key = ModKey.init(ModKey.keycode(config.modKey())),
        .move_offset = env.move_offset,
        .scale = scale,
        .angle = angle,
        .slide = SlideIn.init(1.0, 20.0, 1.0),
    };
    calculateDstRect(&state.dst_rect, deps.window, deps.image.shape.toSize2D(i32), .{});
    return state;
}

// 重新计算 rect
pub fn calculateDstRect(dst_rect: *sdl.c.SDL_FRect, window: *Window, size: Size2D(i32), offset: Point) void {
    const window_width = window.display_width;
    const window_height = window.display_height;

    dst_rect.w = @floatFromInt(size.w);
    dst_rect.h = @floatFromInt(size.h);
    const center_x: f32 = @floatFromInt(@divFloor(window_width - size.w, 2));
    const center_y: f32 = @floatFromInt(@divFloor(window_height - size.h, 2));

    dst_rect.x = center_x + offset.x;
    dst_rect.y = center_y + offset.y;
}
