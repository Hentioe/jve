const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const ui = @import("../ui.zig");
const Allocator = std.mem.Allocator;
const app_env = @import("../app_env.zig");
const Device = @import("../Device.zig");
const pipeline_registry = @import("../pipelines/registry.zig");
const Size2D = @import("shared").Size2D;
const Window = @import("window.zig");
const RenderDeps = @import("diag/RenderDeps.zig");
const loop = @import("diag/loop.zig");
const events = @import("diag/events.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Self = @This();

const WINDOW_SIZE = Size2D(i32){ .w = 1024, .h = 768 };
const WINDOW_OPTIONS = Window.Options{ .windowed = true, .mode = .gpu, .borderless = false };

allocator: Allocator,
window: *Window,
gpu: *const sdl.Gpu,
ass_renderer: ass.Renderer,

pub fn init(allocator: Allocator) Error!Self {
    // 初始化「欢迎」模式
    std.log.info("Initializing diag mode", .{});
    // 创建窗口
    const window = try Window.create(allocator, WINDOW_SIZE, WINDOW_OPTIONS);
    errdefer window.destroy();
    try window.setTitle("错误诊断", .{ .include_content_size = false });
    // 获取显示层共享的 GPU 设备
    const gpu = try Device.getGpu();
    // 绑定窗口到 GPU 设备
    try gpu.claimWindow(window.sdl_window);
    window.gpu_device = gpu;
    // 创建 ass 渲染器
    const ass_renderer = try ass.Renderer.init(try ui.AssLibrary.get());
    // 设置 ass 渲染器字体
    ass_renderer.setFonts(null, ui.DEFAULT_FONT, ass.FONTPROVIDER_AUTODETECT, null, 1);

    return Self{
        .allocator = allocator,
        .window = window,
        .gpu = gpu,
        .ass_renderer = ass_renderer,
    };
}

pub fn deinit(self: *Self) void {
    std.log.info("Deinitializing diag mode", .{});
    self.window.destroy();
    self.ass_renderer.deinit("diag mode");
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    defer Device.discardUploader();
    // 设置 ass 帧尺寸（文字据此相对 PLAY_RES 缩放）
    self.ass_renderer.setFrameSize(WINDOW_SIZE.w, WINDOW_SIZE.h);
    // UI 组件共享的管线注册表
    try pipeline_registry.init(self.allocator, self.window, self.gpu);
    defer pipeline_registry.deinit();
    var widgets = [_]ui.Widget{};
    // 错误消息横幅
    var banner = try ui.TextBanner.init(self.allocator, &self.ass_renderer, WINDOW_SIZE, .{
        .placement = .center,
        .color = .rgba01(0.5, 0.0, 0.0, 0.5),
        .padding_y = 10.0,
    });
    defer banner.deinit();
    const message = if (app_env.writer().takeFatal()) |fatal| fatal.message() else "或许，没有发生错误？";
    try banner.setText(message);

    var deps = try RenderDeps.init(self.allocator, self.window, self.gpu, &widgets, &banner);
    defer deps.deinit();

    var context = events.Context.init(&deps, &banner);

    try self.window.show();
    try loop.run(&deps, &context);

    return .quit;
}
