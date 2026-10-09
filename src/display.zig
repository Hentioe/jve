const std = @import("std");
const sdl = @import("sdl");

pub const preview = @import("display/preview.zig");
pub const gpu = @import("display/gpu.zig");
pub const State = @import("display/State.zig");
pub const Mode = @import("display/enums.zig").Mode;
pub const Welcome = @import("display/Welcome.zig");
pub const Error = @import("display/errors.zig").Error;

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
    sdl.c.SDL_Quit();
}
