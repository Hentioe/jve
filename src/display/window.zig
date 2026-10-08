const std = @import("std");
const c = @import("sdl").c;
const h = @import("sdl").h;
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Mode = @import("enums.zig").Mode;
const Overflow = @import("enums.zig").Overflow;
const ISize = shared.ISize;

const Self = @This();

/// 窗口化时，窗口最多占据屏幕的比例。超出屏幕时按此比例等比缩小。
const SCREEN_FILL_RATIO: f32 = 0.9;

allocator: Allocator,
image_width: i32,
image_height: i32,
display_width: i32,
display_height: i32,
sdl_window: *c.SDL_Window,
windowed: bool, // 是否窗口化
overflow: Overflow = .none, // 图片超出窗口最大限制的方向
mod_key_pressed: bool = false, // 是否按下了 Mod 键
dirty: bool = false,

const Options = struct {
    windowed: bool,
    mode: Mode = .pewview,
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
    // 创建时隐藏
    try h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_HIDDEN_BOOLEAN, 1));
    if (options.mode == .pewview) {
        flags |= c.SDL_WINDOW_TRANSPARENT; // 透明背景
    }
    var overflow: Overflow = .none;
    if (options.windowed) {
        // 设置窗口的初始宽高：图片超出最大限制时按比例缩小，否则使用图片原始尺寸
        const fit = fitToScreen(image_size.w, image_size.h, display_width, display_height);
        overflow = fit.overflow;
        try h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, fit.size.w));
        try h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, fit.size.h));
    } else {
        std.log.info("Borderless mode", .{});
        // 输出显示器尺寸
        std.log.info("Display size: {d}x{d}", .{ display_width, display_height });
        flags |= c.SDL_WINDOW_BORDERLESS;
        flags |= c.SDL_WINDOW_FULLSCREEN;
    }
    // 设置窗口标志
    try h.check(c.SDL_SetNumberProperty(props, c.SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, @intCast(flags)));
    // 创建 SDL 窗口
    const sdl_window = try h.check(c.SDL_CreateWindowWithProperties(props));
    const self_ptr = try allocator.create(Self);
    // 构造结构体
    self_ptr.* = Self{
        .allocator = allocator,
        .windowed = options.windowed,
        .overflow = overflow,
        .image_width = image_size.w,
        .image_height = image_size.h,
        .display_width = display_width,
        .display_height = display_height,
        .sdl_window = sdl_window,
    };
    // 支持拖动窗口
    const callback_data = @constCast(self_ptr); // 把 self 指针作为 callback_data 传递给 hitTestCallback
    try h.check(c.SDL_SetWindowHitTest(sdl_window, hitTestCallback, callback_data));
    // 返回指针
    return self_ptr;
}

pub fn destroy(self: *Self) void {
    // 隐藏窗口
    h.check(c.SDL_HideWindow(self.sdl_window)) catch {}; // 出错不影响窗口关闭，忽略返回值
    c.SDL_DestroyWindow(self.sdl_window);
    self.allocator.destroy(self); // init 在堆上分配了自身
}

pub fn hide(self: *Self) Error!void {
    try h.check(c.SDL_HideWindow(self.sdl_window));
}

pub fn show(self: *Self) Error!void {
    if (self.windowed and self.dirty) {
        std.log.debug("Window is dirty, updating size and position", .{});
        // 重新调整窗口到图片大小：超出最大限制时按比例缩小，并记录超出方向
        const fit = fitToScreen(self.image_width, self.image_height, self.display_width, self.display_height);
        self.overflow = fit.overflow;
        h.check(c.SDL_SetWindowSize(self.sdl_window, fit.size.w, fit.size.h)) catch {
            std.log.warn("Failed to set window size to {d}x{d}", .{ fit.size.w, fit.size.h });
        };
        // 窗口位置重新居中
        h.check(c.SDL_SetWindowPosition(self.sdl_window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED)) catch {
            std.log.warn("Failed to set window position to centered", .{});
        };
        self.dirty = false;
    }
    try h.check(c.SDL_ShowWindow(self.sdl_window));
}

pub fn setTitle(self: *Self, file_name: []const u8) Error!void {
    const titile = try std.fmt.allocPrintSentinel(self.allocator, "{s} ({d}x{d})", .{ file_name, self.image_width, self.image_height }, 0);
    defer self.allocator.free(titile);
    try h.check(c.SDL_SetWindowTitle(self.sdl_window, titile));
}

pub fn imageSizeUpdated(self: *Self, size: ISize(i32)) void {
    if (size.w != self.image_width or size.h != self.image_height) {
        self.image_width = size.w;
        self.image_height = size.h;
        self.dirty = true;
    }
}

/// fitToScreen 的计算结果：窗口尺寸及图片相对最大限制的超出方向。
const FitResult = struct {
    size: ISize(i32),
    overflow: Overflow,
};

/// 根据屏幕尺寸计算窗口允许的最大尺寸（屏幕的 SCREEN_FILL_RATIO），
/// 并将其作为统一的最大限制：无论图片是否超出屏幕，窗口都不会超过该限制。
/// 超出时按比例缩小，未超出时保持图片原始尺寸。同时给出超出方向。
fn fitToScreen(image_width: i32, image_height: i32, display_width: i32, display_height: i32) FitResult {
    const max_width = @as(f32, @floatFromInt(display_width)) * SCREEN_FILL_RATIO;
    const max_height = @as(f32, @floatFromInt(display_height)) * SCREEN_FILL_RATIO;
    const width: f32 = @floatFromInt(image_width);
    const height: f32 = @floatFromInt(image_height);
    // 统一的最大尺寸限制，最多保持原始尺寸（scale 不超过 1）
    const scale = @min(1.0, @min(max_width / width, max_height / height));
    // 判断图片相对最大限制的超出方向
    const overflow: Overflow = if (width > max_width and height > max_height)
        .both
    else if (width > max_width)
        .horizontal
    else if (height > max_height)
        .vertical
    else
        .none;
    return .{
        .size = .{
            .w = @intFromFloat(width * scale),
            .h = @intFromFloat(height * scale),
        },
        .overflow = overflow,
    };
}

fn hitTestCallback(_: ?*c.SDL_Window, _: [*c]const c.SDL_Point, ctx: ?*anyopaque) callconv(.c) c_uint {
    const self: *Self = @ptrCast(@alignCast(ctx));
    if (self.windowed and !self.mod_key_pressed) {
        return c.SDL_HITTEST_DRAGGABLE; // 允许通过拖动窗口的任意位置来移动窗口
    } else {
        return c.SDL_HITTEST_NORMAL; // 如果无边框，不支持拖动
    }
}
