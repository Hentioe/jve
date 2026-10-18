const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Size2D = @import("shared").Size2D;
const Window = @import("window.zig");
const Device = @import("../Device.zig");
const ui = @import("../ui.zig");
const AssLibrary = ui.AssLibrary;
const Text = ui.Text;
const Icon = ui.Icon;
const Widget = ui.Widget;
const TextPipeline = ui.TextPipeline;
const BannerPipeline = ui.BannerPipeline;
const RectPipeline = ui.RectPipeline;
const TextBanner = ui.TextBanner;
const Uploader = @import("Uploader.zig");
const ExitAction = @import("enums.zig").ExitAction;
const RenderDeps = @import("welcome/RenderDeps.zig");
const loop = @import("welcome/loop.zig");
const events = @import("welcome/events.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

const WINDOW_SIZE = Size2D(i32){ .w = 1024, .h = 768 };
const WINDOW_OPTIONS = Window.Options{ .windowed = true, .mode = .gpu, .borderless = false };
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
    try window.setTitle("欢迎使用", .{ .include_content_size = false });
    // 获取显示层共享的 GPU 设备
    const gpu = try Device.getGpu();
    // 绑定窗口到 GPU 设备
    try gpu.claimWindow(window.sdl_window);
    window.gpu_device = gpu;
    // 创建 ass 渲染器
    const ass_renderer = try ass.Renderer.init(try AssLibrary.get());
    // 设置 ass 渲染器字体
    ass_renderer.setFonts(null, ui.DEFAULT_FONT, ass.c.ASS_FONTPROVIDER_AUTODETECT, null, 1);

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
    // 设置 ass 帧尺寸（文字据此相对 PLAY_RES 缩放）
    self.ass_renderer.setFrameSize(WINDOW_SIZE.w, WINDOW_SIZE.h);
    // 所有组件的资源上传共用同一个上传器，最后由外部统一提交
    var uploader = Uploader.init(self.allocator, self.gpu);
    defer uploader.deinit();
    // 纯色矩形背景（Button / TitleBar）共享的渲染管线
    var rect_pipeline = try RectPipeline.init(self.window, self.gpu);
    defer rect_pipeline.deinit();
    // 所有文字/图标组件共享的渲染管线
    var text_pipeline = try TextPipeline.init(self.window, self.gpu);
    defer text_pipeline.deinit();
    // 横幅背景共享的渲染管线
    // todo: 单例化 banner 管线，在 banner 组件中直接获取
    var banner_pipeline = try BannerPipeline.init(self.window, self.gpu);
    defer banner_pipeline.deinit();
    // 创建 logo 文字
    var logo = try Text.init(self.allocator, &self.ass_renderer, LOGO_TEXT, .{
        .font_name = LOGO_FONT,
        .font_size = 32,
        .bold = true,
        .spacing = 25.0,
        .trim = true,
    });
    defer logo.deinit();
    logo.position(ui.LayoutOptions.centered(logo.raster.size(), WINDOW_SIZE, .{ .x = 0, .y = 60 })).debug(debug);
    // 生成图像图标
    var image = try Icon.init(self.allocator, .image, .{ .scale = 2.5 });
    image.position(ui.LayoutOptions.centered(image.raster.size(), WINDOW_SIZE, .{ .x = 0, .y = -60 })).debug(debug);
    defer image.deinit();

    var widgets = [_]Widget{
        try image.toWidget(&uploader, WINDOW_SIZE, &text_pipeline),
        try logo.toWidget(&uploader, WINDOW_SIZE, &text_pipeline),
    };
    // 统一提交所有组件的资源上传
    try uploader.submit();

    // 底部横幅（背景默认红色，测试文本）；帧渲染中一直显示
    var banner = try TextBanner.init(self.allocator, &self.ass_renderer, WINDOW_SIZE, &uploader, &text_pipeline, &banner_pipeline, .{
        .color = .rgba(1.0, 1.0, 1.0, 0), // 半透明白色
    });
    defer banner.deinit();
    try banner.setText(WELCOME_TEXT);

    var deps = try RenderDeps.init(self.allocator, self.window, self.gpu, &widgets, &banner);
    defer deps.deinit();

    var context = events.Context.init(&deps);

    try self.window.show();
    try loop.run(&deps, &context);

    return .quit;
}
