const c = @import("c.zig").c;
const Error = @import("errors.zig").Error;
const printSdlError = @import("helper.zig").printSdlError;

const Self = @This();

has_border: bool,
width: usize = 0,
height: usize = 0,
sdl_window: ?*c.SDL_Window = null,

pub fn init(width: usize, height: usize, has_border: bool) Error!Self {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        printSdlError();
        return Error.SdlInitFailed;
    }
    // 创建窗口
    const sdl_window = c.SDL_CreateWindow(
        "Image Viewer",
        @intCast(width),
        @intCast(height),
        c.SDL_EVENT_WINDOW_SHOWN | c.SDL_WINDOW_BORDERLESS | c.SDL_WINDOW_TRANSPARENT,
    );
    if (sdl_window == null) {
        printSdlError();
        return Error.SdlInitFailed;
    }

    // 支持拖动窗口
    _ = c.SDL_SetWindowHitTest(sdl_window, hitTestCallback, null);
    return Self{
        .has_border = has_border,
        .width = width,
        .height = height,
        .sdl_window = sdl_window,
    };
}

pub fn toggleBorder(self: *Self) void {
    self.has_border = !self.has_border;
    _ = c.SDL_SetWindowBordered(self.sdl_window, self.has_border);
}

pub fn deinit(self: Self) void {
    c.SDL_DestroyWindow(self.sdl_window);
    c.SDL_Quit();
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, _: ?*anyopaque) callconv(.c) c_uint {
    return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
}
