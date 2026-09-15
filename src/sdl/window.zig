const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;

const Self = @This();

allocator: std.mem.Allocator,
image_width: usize,
image_height: usize,
display_width: usize,
display_height: usize,
has_border: bool,
sdl_window: ?*c.SDL_Window,

pub fn init(allocator: std.mem.Allocator, image_width: usize, image_height: usize, has_border: bool) Error!*Self {
    // 初始化 SDL
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        helper.printSdlError();
        return Error.SdlInitFailed;
    }
    // 获取主显示器尺寸
    const display_mode = c.SDL_GetCurrentDisplayMode(c.SDL_GetPrimaryDisplay());
    const display_width: usize = @intCast(display_mode.*.w);
    const display_height: usize = @intCast(display_mode.*.h);
    std.debug.print("Display: width={d}, height={d}\n", .{ display_width, display_height });
    // 创建窗口
    const sdl_window = c.SDL_CreateWindow(
        "Image Viewer",
        @intCast(display_width),
        @intCast(display_height),
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
        .image_width = image_width,
        .image_height = image_height,
        .display_width = display_width,
        .display_height = display_height,
        .sdl_window = sdl_window,
    };
    // 支持拖动窗口
    const callback_data = @constCast(self_ptr); // 把 self 指针作为 callback_data 传递给 hitTestCallback
    _ = c.SDL_SetWindowHitTest(sdl_window, hitTestCallback, callback_data);
    // 返回指针
    return self_ptr;
}

pub fn toggleBorder(self: *Self) void {
    self.has_border = !self.has_border;
    var window_width: c_int = @intCast(self.image_width);
    var window_height: c_int = @intCast(self.image_height);
    if (!self.has_border) {
        window_height = @intCast(self.display_height);
        window_width = @intCast(self.display_width);
    }
    // 设置窗口大小
    _ = c.SDL_SetWindowSize(self.sdl_window, window_width, window_height);
    // 让窗口居中
    _ = c.SDL_SetWindowPosition(self.sdl_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
    // 显示窗口边框
    _ = c.SDL_SetWindowBordered(self.sdl_window, self.has_border);
}

pub fn imageSizeUpdated(self: *Self, new_width: usize, new_height: usize) void {
    if (new_width != self.image_width and new_height != self.image_height) {
        std.debug.print("new_width: {d}, new_height: {d}\n", .{ new_width, new_height });
        self.image_width = new_width;
        self.image_height = new_height;
    }
}

pub fn currentSize(self: *Self) struct { usize, usize } {
    if (self.has_border) {
        return .{ self.image_width, self.image_height };
    } else {
        return .{ self.display_width, self.display_height };
    }
}

pub fn deinit(self: *Self) void {
    c.SDL_DestroyWindow(self.sdl_window);
    c.SDL_Quit();
    self.allocator.destroy(self);
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, self_ptr: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(self_ptr)); // 还原回调数据
    if (self.has_border) {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    } else {
        return c.SDL_HITTEST_NORMAL; // 如果无边框，不支持拖动
    }
}
