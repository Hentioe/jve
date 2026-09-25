const c = @import("sdl/c.zig").c;
const h = @import("sdl/helper.zig");
pub const Error = @import("sdl/errors.zig").Error;
pub const Backend = @import("sdl/enums.zig").Backend;

pub fn init() Error!void {
    // 设置提示
    _ = h.check(c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "x11")) or return Error.SdlInitFailed; // todo: 配置化驱动
    // 强制 1:1 像素映射
    _ = h.check(c.SDL_SetHint(c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1")) or return Error.SdlInitFailed;
    // 初始化 SDL
    _ = h.check(c.SDL_Init(c.SDL_INIT_VIDEO)) or return Error.SdlInitFailed;
    // 初始化 ShaderCross
    // todo: 让后端自己去初始化
    _ = h.check(c.SDL_ShaderCross_Init()) or return Error.SdlShaderCrossInitFailed;
}

pub fn deinit() void {
    c.SDL_Quit();
}
