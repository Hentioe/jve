const std = @import("std");
const c = @import("sdl/c.zig").c;
const h = @import("sdl/helper.zig");
pub const Error = @import("sdl/errors.zig").Error;
pub const Backend = @import("sdl/enums.zig").Backend;

pub fn init() Error!void {
    // 设置提示
    if (!h.check(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "x11"))) return Error.SdlInitFailed; // todo: 配置化驱动
    // 强制 1:1 像素映射
    if (!h.check(c.SDL_SetHint(c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1"))) return Error.SdlInitFailed;
    // 初始化 SDL
    if (!h.check(c.SDL_Init(c.SDL_INIT_VIDEO))) return Error.SdlInitFailed;
    // 设置应用元数据
    if (!h.check(c.SDL_SetAppMetadata("JVE", "0.0.0", "jve"))) {
        std.log.warn("Failed to set app metadata", .{});
    }
    // 设置应用 ID
    if (!h.check(c.SDL_SetHint(c.SDL_HINT_APP_ID, "jve"))) {
        std.log.warn("Failed to set app ID", .{});
    }
    // 初始化 ShaderCross
    // todo: 让后端自己去初始化
    if (!h.check(c.SDL_ShaderCross_Init())) return Error.SdlShaderCrossInitFailed;
}

pub fn deinit() void {
    c.SDL_Quit();
}
