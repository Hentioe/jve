const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Backend = @import("enums.zig").Backend;
const ISize = shared.ISize;

const Self = @This();

allocator: Allocator,
image_width: i32,
image_height: i32,
display_width: i32,
display_height: i32,
sdl_window: *c.SDL_Window,
windowed: bool, // 是否窗口化
mod_key_pressed: bool = false, // 是否按下了 Mod 键
dirty: bool = false,

const Options = struct {
    windowed: bool,
    backend: Backend = .sdl_renderer,
};

pub fn create(allocator: Allocator, image_size: ISize(i32), options: Options) Error!*Self {
    // 获取主显示器尺寸
    const display_mode = c.SDL_GetCurrentDisplayMode(c.SDL_GetPrimaryDisplay());
    const display_width = display_mode.*.w;
    const display_height = display_mode.*.h;
    // 创建窗口标识
    var flags: u64 = c.SDL_EVENT_WINDOW_SHOWN | c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
    // 创建窗口属性
    const props = c.SDL_CreateProperties();
    defer c.SDL_DestroyProperties(props);
    if (options.backend == .sdl_renderer) {
        flags |= c.SDL_WINDOW_TRANSPARENT;
    }
    if (options.windowed) {
        // 设置窗口的初始宽高为图片的宽高
        if (!h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, image_size.w))) return Error.SdlSetNumberPropertyFailed;
        if (!h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, image_size.h))) return Error.SdlSetNumberPropertyFailed;
    } else {
        std.log.info("Borderless mode", .{});
        // 输出显示器尺寸
        std.log.info("Display size: {d}x{d}", .{ display_width, display_height });
        flags |= c.SDL_WINDOW_BORDERLESS;
        flags |= c.SDL_WINDOW_FULLSCREEN;
    }
    // 设置窗口标志
    if (!h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags)))) return Error.SdlSetNumberPropertyFailed;
    // 创建 SDL 窗口
    const sdl_window = c.SDL_CreateWindowWithProperties(props) orelse {
        h.printError();
        return Error.SdlCreateWindowFailed;
    };
    const self_ptr = try allocator.create(Self);
    // 构造结构体
    self_ptr.* = Self{
        .allocator = allocator,
        .windowed = options.windowed,
        .image_width = image_size.w,
        .image_height = image_size.h,
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
    if (self.windowed) {
        if (self.dirty) {
            std.log.debug("Window is dirty, updating size and position", .{});
            // 重新调整窗口到图片大小
            if (!h.check(c.SDL_SetWindowSize(self.sdl_window, self.image_width, self.image_height))) {
                std.log.warn("Failed to set window size to {d}x{d}", .{ self.image_width, self.image_height });
            }
            // 窗口位置重新居中
            if (!h.check(c.SDL_SetWindowPosition(self.sdl_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED))) {
                std.log.warn("Failed to set window position to centered", .{});
            }
            self.dirty = false;
        }
    }
    if (!h.check(c.SDL_ShowWindow(self.sdl_window))) return Error.SdlShowWindowFailed;
}

pub fn setTitle(self: *Self, file_name: []const u8) Error!void {
    const titile = try std.fmt.allocPrintSentinel(self.allocator, "{s} ({d}x{d})", .{ file_name, self.image_width, self.image_height }, 0);
    defer self.allocator.free(titile);
    if (!h.check(c.SDL_SetWindowTitle(self.sdl_window, titile))) return Error.SdlSetWindowTitleFailed;
}

pub fn imageSizeUpdated(self: *Self, size: ISize(i32)) void {
    if (size.w != self.image_width or size.h != self.image_height) {
        self.image_width = size.w;
        self.image_height = size.h;
        self.dirty = true;
    }
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, self_ptr: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(self_ptr)); // 还原回调数据
    if (self.windowed and !self.mod_key_pressed) {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    } else {
        return c.SDL_HITTEST_NORMAL; // 如果无边框，不支持拖动
    }
}
