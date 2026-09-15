const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;

const Self = @This();

allocator: std.mem.Allocator,
width: usize = 0,
height: usize = 0,
has_border: bool,
sdl_window: ?*c.SDL_Window = null,

pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, has_border: bool) Error!*Self {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        helper.printSdlError();
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
        helper.printSdlError();
        return Error.SdlInitFailed;
    }

    const self_ptr = try allocator.create(Self);

    // 构造结构体
    self_ptr.* = Self{
        .allocator = allocator,
        .has_border = has_border,
        .width = width,
        .height = height,
        .sdl_window = sdl_window,
    };
    // 支持拖动窗口
    const callback_data = @constCast(self_ptr); // 把 self 指针作为 callback_data 传递给 hitTestCallback
    _ = c.SDL_SetWindowHitTest(sdl_window, hitTestCallback, callback_data);
    // 返回结构体
    return self_ptr;
}

pub fn toggleBorder(self: *Self) void {
    self.has_border = !self.has_border;
    _ = c.SDL_SetWindowBordered(self.sdl_window, self.has_border);
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyWindow(self.sdl_window);
    c.SDL_Quit();
    self.allocator.destroy(self);
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, self_ptr: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(self_ptr)); // 还原回调数据
    if (self.has_border) {
        return c.SDL_HITTEST_NORMAL; // 如果有边框，不支持拖动
    } else {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    }
}
