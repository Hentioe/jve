const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const AssLibrary = @import("../ui/AssLibrary.zig");
const Size2D = @import("shared").Size2D;
const Window = @import("window.zig");
const Device = @import("Device.zig");
const RenderDeps = @import("welcome/RenderDeps.zig");
const loop = @import("welcome/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const ui = @import("../ui.zig");
const Text = ui.Text;
const Icon = ui.Icon;
const TextPipeline = @import("TextPipeline.zig");
const Drawable = @import("../ui/Drawable.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

const WINDOW_SIZE = Size2D(i32){ .w = 1024, .h = 768 };
const WINDOW_OPTIONS = Window.Options{ .windowed = true, .mode = .gpu };
const LOGO_TEXT = "JVE";
const LOGO_FONT = "Liberation Serif";
const WELCOME_TEXT = "JVE 是一个图像查看器";

const debug = builtin.mode == .Debug;

allocator: Allocator,
window: *Window,
gpu: *const sdl.Gpu, // Gpu 是全局共享的，不属于 Viewer 管理
ass_renderer: ass.Renderer,

pub fn init(allocator: Allocator) Error!Self {
    // 初始化「欢迎」模式
    std.log.info("Initializing welcome mode", .{});
    // 创建窗口
    const window = try Window.create(allocator, WINDOW_SIZE, WINDOW_OPTIONS);
    errdefer window.destroy();
    // 获取显示层共享的 GPU 设备
    const gpu = try Device.get();
    // 绑定窗口到 GPU 设备
    try gpu.claimWindow(window.sdl_window);
    window.gpu_device = gpu;
    // 创建 ass 渲染器
    const ass_renderer = try ass.Renderer.init(try AssLibrary.get());
    // 设置 ass 渲染器字体
    ass_renderer.setFonts(null, "Arial", ass.c.ASS_FONTPROVIDER_AUTODETECT, null, 1);

    return Self{
        .allocator = allocator,
        .window = window,
        .gpu = gpu,
        .ass_renderer = ass_renderer,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing welcome mode", .{});
    self.window.destroy();
    self.ass_renderer.deinit("welcome mode");
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    // 设置 ass 帧尺寸
    self.ass_renderer.setFrameSize(WINDOW_SIZE.w, WINDOW_SIZE.h);
    // 创建 logo 文字
    var logo = try Text.init(self.allocator, &self.ass_renderer, LOGO_TEXT, .{
        .font_name = LOGO_FONT,
        .font_size = 32,
        .bold = true,
        .spacing = 25.0,
        .trim = true,
    });
    defer logo.deinit();
    logo.position(TextPipeline.Options.centered(logo.raster.size(), WINDOW_SIZE, .{ .x = 0, .y = 60 })).debug(debug);
    var welcome = try Text.init(self.allocator, &self.ass_renderer, WELCOME_TEXT, .{
        .font_name = "Noto Sans",
        .font_size = 13,
        .color = 0xFFFFFF33,
        .bold = false,
        .spacing = 1.0,
        .trim = true,
    });
    defer welcome.deinit();
    welcome.position(.{
        .x = @floatFromInt(WINDOW_SIZE.w / 2 - @divTrunc(@as(i32, @intCast(welcome.raster.width)), 2)),
        .y = @floatFromInt(@as(u32, WINDOW_SIZE.h) - 100),
    }).debug(debug);
    // // 生成关闭图标
    // var close = try Icon.init(self.allocator, .close, .{ .color = 0xFFFFFF80 });
    // defer close.deinit();
    // // 生成最小化图标
    // var minimize = try Icon.init(self.allocator, .minimize, .{ .color = 0xFFFFFF80 });
    // defer minimize.deinit();
    // 生成图像图标
    var image = try Icon.init(self.allocator, .image, .{ .scale = 2.5 });
    image.position(TextPipeline.Options.centered(image.raster.size(), WINDOW_SIZE, .{ .x = 0, .y = -60 })).debug(debug);
    defer image.deinit();

    var drawables = [_]Drawable{
        try image.toDrawable(self.window, self.gpu, WINDOW_SIZE),
        try logo.toDrawable(self.window, self.gpu, WINDOW_SIZE),
        try welcome.toDrawable(self.window, self.gpu, WINDOW_SIZE),
    };

    var deps = try RenderDeps.init(self.allocator, self.window, self.gpu, &drawables);
    defer deps.deinit();

    try self.window.show();
    try loop.run(&deps);

    return .quit;
}
