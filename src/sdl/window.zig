const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Backend = @import("enums.zig").Backend;

const Self = @This();

allocator: std.mem.Allocator,
image_width: i32,
image_height: i32,
display_width: i32,
display_height: i32,
has_border: bool,
leader_pressed: bool = false,
sdl_window: *c.SDL_Window,

const Options = struct {
    has_border: bool = true,
    backend: Backend = .sdl_renderer,
};

pub fn create(allocator: std.mem.Allocator, image_width: i32, image_height: i32, options: Options) Error!*Self {
    // 获取主显示器尺寸
    const display_mode = c.SDL_GetCurrentDisplayMode(c.SDL_GetPrimaryDisplay());
    const display_width = display_mode.*.w;
    const display_height = display_mode.*.h;
    // 创建窗口
    var flags: u64 = c.SDL_EVENT_WINDOW_SHOWN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    if (options.backend == .sdl_renderer) {
        flags |= c.SDL_WINDOW_TRANSPARENT;
    }
    if (!options.has_border) {
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
        .has_border = options.has_border,
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

// 待删除：此后端不再需要窗口模式
// pub fn toggleBorder(self: *Self) void {
//     self.has_border = !self.has_border;
//     var window_width = self.image_width;
//     var window_height = self.image_height;
//     if (!self.has_border) {
//         window_height = self.display_height;
//         window_width = self.display_width;
//     }
//     // 设置窗口大小
//     c.SDL_SetWindowSize(self.sdl_window, @intCast(window_width), @intCast(window_height));
//     // 让窗口居中
//     c.SDL_SetWindowPosition(self.sdl_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED);
//     // 显示窗口边框
//     c.SDL_SetWindowBordered(self.sdl_window, self.has_border);
// }

pub fn hide(self: *Self) Error!void {
    if (!h.check(c.SDL_HideWindow(self.sdl_window))) return Error.SdlHideWindowFailed;
}

pub fn show(self: *Self) Error!void {
    if (!h.check(c.SDL_ShowWindow(self.sdl_window))) return Error.SdlShowWindowFailed;
}

pub fn setTitle(self: *Self, file_name: []const u8) Error!void {
    const titile = try std.fmt.allocPrintSentinel(self.allocator, "{s} ({d}x{d})", .{ file_name, self.image_width, self.image_height }, 0);
    defer self.allocator.free(titile);
    if (!h.check(c.SDL_SetWindowTitle(self.sdl_window, titile))) return Error.SdlSetWindowTitleFailed;
}

pub fn imageSizeUpdated(self: *Self, new_width: i32, new_height: i32) void {
    if (new_width != self.image_width and new_height != self.image_height) {
        self.image_width = new_width;
        self.image_height = new_height;
    }
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, self_ptr: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(self_ptr)); // 还原回调数据
    if (self.has_border and !self.leader_pressed) {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    } else {
        return c.SDL_HITTEST_NORMAL; // 如果无边框，不支持拖动
    }
}
