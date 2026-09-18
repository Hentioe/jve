const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Backend = @import("enums.zig").Backend;

pub fn initialize(backend: Backend) Error!void {
    // 设置提示
    if (!c.SDL_SetHint(c.SDL_HINT_VIDEO_DRIVER, "x11")) { // todo: 配置化驱动
        helper.printError();
        return Error.SdlInitFailed;
    }
    if (!c.SDL_SetHint(c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1")) { // 强制 1:1 像素映射
        helper.printError();
        return Error.SdlInitFailed;
    }
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        helper.printError();
        return Error.SdlInitFailed;
    }
    // 初始化 sdl_gpu 特有的组件
    if (backend == .SdlGpu) {
        var failed = false;
        if (!c.SDL_ShaderCross_Init()) {
            failed = true;
            return Error.SdlShaderCrossInitFailed;
        }
        if (!c.TTF_Init()) {
            failed = true;
            return Error.SdlTTFInitFailed;
        }
        if (failed) {
            helper.printError();
        }
    }
}
