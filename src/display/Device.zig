const std = @import("std");
const sdl = @import("sdl");
const Error = @import("errors.zig").Error;

// 显示层唯一的 GPU 设备。多个窗口可绑定到同一设备上，
// 因此全局只创建一个，由 display 负责其生命周期（懒创建、统一销毁）。
var instance: ?sdl.Gpu = null;
// 已编译的背景着色器（可能来自用户配置）
var background_shader: ?*sdl.GPUShader = null;

// 懒创建并返回只读指针。
pub fn get() Error!*const sdl.Gpu {
    if (instance == null) instance = try sdl.Gpu.create();
    return &instance.?;
}

// 唯一销毁点，由 display.deinit 在 SDL_Quit 之前调用。
pub fn destroy() void {
    if (instance) |*device| {
        device.releaseGPUShader(background_shader);
        device.destroy();
        instance = null;
    }
}

pub fn setBackgroundShader(shader: ?*sdl.GPUShader) void {
    std.debug.assert(shader != null);
    background_shader = shader;
}

pub fn getBackgroundShader() ?*sdl.GPUShader {
    return background_shader;
}
