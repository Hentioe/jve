const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Backend = @import("enums.zig").Backend;

const Self = @This();

allocator: Allocator,
image_width: i32,
image_height: i32,
display_width: i32,
display_height: i32,
sdl_window: *c.SDL_Window,
windowed: bool, // 窗口化的？
leader_pressed: bool = false, // 是否按下了 Leader 键

const Options = struct {
    windowed: bool = true,
    backend: Backend = .sdl_renderer,
};

pub fn create(allocator: Allocator, image_width: i32, image_height: i32, options: Options) Error!*Self {
    // 获取主显示器尺寸
    const display_mode = c.SDL_GetCurrentDisplayMode(c.SDL_GetPrimaryDisplay());
    const display_width = display_mode.*.w;
    const display_height = display_mode.*.h;
    // 创建窗口
    var flags: u64 = c.SDL_EVENT_WINDOW_SHOWN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (options.backend == .sdl_renderer) {
        flags |= c.SDL_WINDOW_TRANSPARENT;
    }
    if (!options.windowed) {
        std.log.info("Borderless mode", .{});
        // 输出显示器尺寸
        std.log.info("Display size: {d}x{d}", .{ display_width, display_height });
        flags |= c.SDL_WINDOW_BORDERLESS;
        flags |= c.SDL_WINDOW_FULLSCREEN;
    }
    const sdl_window = c.SDL_CreateWindow("Image Viewer", image_width, image_height, flags) orelse {
        h.printError();
        return Error.SdlCreateWindowFailed;
    };
    const self_ptr = try allocator.create(Self);
    // 构造结构体
    self_ptr.* = Self{
        .allocator = allocator,
        .windowed = options.windowed,
        .image_width = image_width,
        .image_height = image_height,
        .display_width = display_width,
        .display_height = display_height,
        .sdl_window = sdl_window,
    };
    // 支持拖动窗口
    const callback_data = @constCast(self_ptr); // 把 self 指针作为 callback_data 传递给 hitTestCallback
    if (!h.check(c.SDL_SetWindowHitTest(sdl_window, hitTestCallback, callback_data))) return Error.SdlSetWindowHitTestFailed;
    // 返回指针
    return self_ptr;
}

pub fn destroy(self: *Self) void {
    // 隐藏窗口
    _ = h.check(c.SDL_HideWindow(self.sdl_window)); // 出错不影响窗口关闭，忽略返回值
    c.SDL_DestroyWindow(self.sdl_window);
    self.allocator.destroy(self); // init 在堆上分配了自身
}

pub fn hide(self: *Self) Error!void {
    if (!h.check(c.SDL_HideWindow(self.sdl_window))) return Error.SdlHideWindowFailed;
}

pub fn show(self: *Self) Error!void {
    if (self.windowed) { // 显示前根据图片尺寸调整窗口
        // 窗口缩放到图片大小
        if (!h.check(c.SDL_SetWindowSize(self.sdl_window, self.image_width, self.image_height))) {
            std.log.warn("Failed to set window size to {d}x{d}", .{ self.image_width, self.image_height });
        }
        // 窗口位置居中
        if (!h.check(c.SDL_SetWindowPosition(self.sdl_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED))) {
            std.log.warn("Failed to set window position to centered", .{});
        }
    }
    if (!h.check(c.SDL_ShowWindow(self.sdl_window))) return Error.SdlShowWindowFailed;
}

pub fn setTitle(self: *Self, file_name: []const u8) Error!void {
    const titile = try std.fmt.allocPrintSentinel(self.allocator, "{s} ({d}x{d})", .{ file_name, self.image_width, self.image_height }, 0);
    defer self.allocator.free(titile);
    if (!h.check(c.SDL_SetWindowTitle(self.sdl_window, titile))) return Error.SdlSetWindowTitleFailed;
}

pub fn imageSizeUpdated(self: *Self, width: i32, height: i32) void {
    if (width != self.image_width and height != self.image_height) {
        self.image_width = width;
        self.image_height = height;
    }
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, self_ptr: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(self_ptr)); // 还原回调数据
    if (self.windowed and !self.leader_pressed) {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    } else {
        return c.SDL_HITTEST_NORMAL; // 如果无边框，不支持拖动
    }
}
