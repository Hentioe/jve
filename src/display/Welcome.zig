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
const icons = ui.icons;
const TextPipeline = @import("TextPipeline.zig");
const TextPair = @import("TextPair.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

const WINDOW_SIZE = Size2D(i32){ .w = 1024, .h = 768 };
const WINDOW_OPTIONS = Window.Options{ .windowed = true, .mode = .gpu };
const LOGO_TEXT = "JVE";
const LOGO_FONT = "Liberation Serif";

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
    var logo_text = try Text.init(self.allocator, &self.ass_renderer, LOGO_TEXT);
    defer logo_text.deinit();
    var logo = try logo_text.render(Text.Options{
        .font_name = LOGO_FONT,
        .font_size = 32,
        .bold = true,
        .spacing = 25.0,
        .trim = true,
    });
    defer logo.deinit();
    // // 生成关闭图标
    // var close_icon = try Icon.render(self.allocator, icons.close, .{ .color = 0xFFFFFF80 });
    // defer close_icon.deinit();
    // // 生成最小化图标
    // var minimize_icon = try Icon.render(self.allocator, icons.minimize, .{ .color = 0xFFFFFF80 });
    // defer minimize_icon.deinit();
    // 生成图像图标
    var image = try Icon.render(self.allocator, icons.image, .{ .scale = 2.5 });
    defer image.deinit();

    const text_pairs = &[_]TextPair{
        TextPair.init(&logo, TextPipeline.Options.centered(.{ .w = logo.width, .h = logo.height }, WINDOW_SIZE, .{ .x = 0, .y = 60 }, debug)),
        // TextPair.init(&close_icon, TextPipeline.Options{ .position = .{ .x = 0, .y = 0 }, .debug = debug }),
        // TextPair.init(&minimize_icon, TextPipeline.Options{ .position = .{ .x = @floatFromInt(close_icon.width), .y = 0 }, .debug = debug }),
        TextPair.init(&image, TextPipeline.Options.centered(.{ .w = image.width, .h = image.height }, WINDOW_SIZE, .{ .x = 0, .y = -60 }, debug)),
    };

    var render_deps = try RenderDeps.init(self.allocator, self.window, self.gpu, WINDOW_SIZE, text_pairs);
    defer render_deps.deinit();

    try self.window.show();
    try loop.run(&render_deps);

    return .quit;
}
