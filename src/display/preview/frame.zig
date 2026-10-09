const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const RenderDeps = @import("RenderDeps.zig");
const State = @import("State.zig");
const Size2D = shared.Size2D;
const Point = shared.Point(f32);
const Error = @import("../errors.zig").Error;

pub fn render(deps: *RenderDeps, state: *State) Error!void {
    // 根据状态执行渲染
    if (state.dirty or state.scale.state == .running or state.angle.state == .running or state.slide.isRunning()) {
        if (state.scale.state == .running) {
            if (state.scale.isNearFinished()) {
                std.log.debug("Scale is near finished, diff: {d}", .{state.scale.target - state.scale.current});
                state.scale.finish();
            } else {
                state.scale.nextStep(state.delta.value);
            }
            std.log.debug("current_scale: {d}, target_scale: {d}, diff: {d}", .{ state.scale.current, state.scale.target, state.scale.target - state.scale.current });
        }
        if (state.angle.state == .running) {
            if (state.angle.isNearFinished()) {
                std.log.debug("Angle is near finished, diff: {d}", .{state.angle.target - state.angle.current});
                state.angle.finish();
            } else {
                state.angle.nextStep(state.delta.value);
            }
        }
        if (state.slide.isRunning()) {
            state.slide.nextStep(state.delta.value);
        }
        // 如果没有动画了，表示渲染干净了
        state.dirty = state.scale.state == .running or state.angle.state == .running or state.slide.isRunning();
        // 计算尺寸
        const f_size = deps.image.shape.toSize2D(f32);
        const new_size: Size2D(i32) = .{ .w = @intFromFloat(f_size.w * state.scale.current), .h = @intFromFloat(f_size.h * state.scale.current) };
        const slide_offset = Point{ .x = state.move_offset.x + @as(f32, @floatCast(state.slide.offset)), .y = state.move_offset.y };
        State.calculateDstRect(&state.dst_rect, deps.window, new_size, slide_offset);
        deps.window.imageSizeUpdated(deps.image.shape.toSize2D(i32));
    }
    const render_angle: f64 = if (state.slide.isRunning()) state.slide.angle else state.angle.current;
    const alpha: u8 = if (deps.window.windowed) 255 else 60; // 根据边框模式设置背景透明度
    try deps.renderer.setRenderDrawColor(0, 0, 0, alpha); // 设置白色背景
    try deps.renderer.renderClear();
    try deps.renderer.renderTextureRotated(deps.texture, null, &state.dst_rect, render_angle, null, sdl.c.SDL_FLIP_NONE);
    try deps.renderer.renderPresent();
}
