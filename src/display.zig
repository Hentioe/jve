const std = @import("std");
const sdl = @import("sdl");
const app_env = @import("app_env.zig");
const Device = @import("display/Device.zig");

pub const Viewer = @import("display/Viewer.zig");
pub const Welcome = @import("display/Welcome.zig");
pub const Error = @import("display/errors.zig").Error;

// 显示模式的 Viewer 缓存：窗口、渲染器、GPU 等资源会按需惰性创建，并在模式切换间复用。
var preview_viewer: ?Viewer = null;
var gpu_viewer: ?Viewer = null;

// 惰性创建并复用指定模式的 Viewer。
fn viewerFor(mode: Viewer.Mode) Error!*Viewer {
    const slot = switch (mode) {
        .preview => &preview_viewer,
        .gpu => &gpu_viewer,
    };
    if (slot.* == null) {
        slot.* = try Viewer.create(app_env.reader().allocator, mode);
        if (mode == .preview) app_env.writer().preview_initialized = true;
    }
    return &slot.*.?;
}

pub fn show(mode: Viewer.Mode) Error!void {
    var current = mode;
    while (true) {
        const viewer = try viewerFor(current);
        current = switch (try viewer.show()) {
            .quit => return, // 退出
            .toggle => switch (current) { // 切换到另一个模式
                .preview => .gpu,
                .gpu => .preview,
            },
        };
    }
}

pub fn init() Error!void {
    // 设置提示
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_DRIVER, "x11")); // todo: 配置化驱动
    // 强制 1:1 像素映射
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1"));
    // 初始化 SDL
    try sdl.check(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    // 设置应用元数据
    sdl.check(sdl.c.SDL_SetAppMetadata("JVE", "0.0.0", "jve")) catch {
        std.log.warn("Failed to set app metadata", .{});
    };
    // 设置应用 ID
    sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_APP_ID, "jve")) catch {
        std.log.warn("Failed to set app ID", .{});
    };
    // 初始化 ShaderCross
    // todo: 让后端自己去初始化
    try sdl.check(sdl.c.SDL_ShaderCross_Init());
}

pub fn deinit() void {
    // 先销毁显示资源（窗口会从设备解绑），再销毁设备，最后退出 SDL。
    if (preview_viewer) |viewer| viewer.destroy();
    if (gpu_viewer) |viewer| viewer.destroy();
    preview_viewer = null;
    gpu_viewer = null;
    Device.destroy();
    sdl.c.SDL_Quit();
}
