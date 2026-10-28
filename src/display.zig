const std = @import("std");
const sdl = @import("sdl");
const app_env = @import("app_env.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Device = @import("Device.zig");
const DisplayMode = @import("config.zig").DisplayMode;

pub const Viewer = @import("display/Viewer.zig");
pub const Welcome = @import("display/Welcome.zig");
pub const Diag = @import("display/Diag.zig");
pub const Error = @import("display/errors.zig").Error;

// 显示模式的 Viewer 缓存：窗口、渲染器、GPU 等资源会按需惰性创建，并在模式切换间复用。
var preview_viewer: ?Viewer = null;
var gpu_viewer: ?Viewer = null;

// 惰性创建并复用指定模式的 Viewer。
fn viewerFor(io: Io, allocator: Allocator, mode: DisplayMode) Error!*Viewer {
    const slot = switch (mode) {
        .preview => &preview_viewer,
        .gpu => &gpu_viewer,
    };
    if (slot.* == null) {
        slot.* = try Viewer.create(io, allocator, mode);
        if (mode == .preview) app_env.writer().preview_initialized = true;
    }
    return &slot.*.?;
}

pub fn show(io: Io, allocator: Allocator, mode: DisplayMode) Error!void {
    var current = mode;
    while (true) {
        const viewer = try viewerFor(io, allocator, current);
        current = switch (try viewer.show()) {
            .quit => return, // 退出
            .toggle => switch (current) { // 切换到另一个模式
                .preview => .gpu,
                .gpu => .preview,
            },
        };
    }
}

pub fn init(allocator: std.mem.Allocator) Error!void {
    // 设备及其上传器由 display 统一管理
    Device.init(allocator);
    // 设置提示
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_DRIVER, "x11")); // todo: 配置化驱动
    // 强制 1:1 像素映射
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1"));
    // 初始化 SDL
    try sdl.check(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    // 设置应用元数据
    try sdl.check(sdl.c.SDL_SetAppMetadata("JVE", "0.0.0", "jve"));
    // 设置应用 ID
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_APP_ID, "jve"));
    // 点击获得焦点时触发点击事件
    try sdl.check(sdl.c.SDL_SetHint(sdl.HINT_MOUSE_FOCUS_CLICKTHROUGH, "1"));
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
