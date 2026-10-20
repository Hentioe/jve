const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const Uploader = @import("display/Uploader.zig");

var allocator: ?Allocator = null;
// 显示层唯一的 GPU 设备。多个窗口可绑定到同一设备上，
// 因此全局只创建一个，由 display 负责其生命周期（懒创建、统一销毁）。
var gpu: ?sdl.Gpu = null;
// 唯一的 GPU 上传器，与设备同生命周期。
var uploader: ?Uploader = null;
// 已编译的背景着色器（可能来自用户配置）
var background_shader: ?*sdl.GPUShader = null;

/// 由 display.init 在创建任何 GPU 资源之前调用。
pub fn init(alloc: Allocator) void {
    allocator = alloc;
}

/// 懒创建并返回唯一 Gpu 实例
pub fn getGpu() sdl.Error!*const sdl.Gpu {
    if (gpu == null) gpu = try sdl.Gpu.create();
    return &gpu.?;
}

/// 获取唯一的上传器（懒创建，复用同一个 Gpu 实例）。
pub fn getUploader() sdl.Error!*Uploader {
    if (uploader == null) uploader = Uploader.init(allocator.?, try getGpu());
    return &uploader.?;
}

/// 丢弃上传器中尚未提交的任务，避免跨会话残留。
pub fn discardUploader() void {
    if (uploader) |*u| u.discard();
}

/// 由 display.deinit 在 SDL_Quit 之前调用。
pub fn destroy() void {
    if (uploader) |*u| {
        u.deinit();
        uploader = null;
    }
    if (gpu) |*device| {
        device.releaseGPUShader(background_shader);
        device.destroy();
        gpu = null;
    }
    allocator = null;
}

pub fn setBackgroundShader(shader: ?*sdl.GPUShader) void {
    std.debug.assert(shader != null);
    background_shader = shader;
}

pub fn getBackgroundShader() ?*sdl.GPUShader {
    return background_shader;
}
