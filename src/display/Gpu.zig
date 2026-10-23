const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const shared = @import("shared");
const config = @import("../config.zig");
const ui = @import("../ui.zig");
const gallery = @import("../gallery.zig");
const Window = @import("window.zig");
const Device = @import("../Device.zig");
const app_env = @import("../app_env.zig");
const shader = @import("../shader.zig");
const Allocator = std.mem.Allocator;
const RenderDeps = @import("gpu/RenderDeps.zig");
const events = @import("gpu/events.zig");
const pipelines = @import("../pipelines.zig");
const loop = @import("gpu/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Self = @This();

// 组件总量
const MAX_WIDGETS = 1; // 当前仅有 title_bar 组件

gpa: Allocator,
window: *Window,
device: *const sdl.Gpu,
shaders: ?shader.loaded.All,
ass_renderer: ass.Renderer,

pub fn init(allocator: Allocator) Error!Self {
    // 初始化 GPU 模式
    std.log.info("Initializing GPU mode", .{});
    const image = try gallery.current();
    const image_size = image.shape.toSize2D(i32);
    // 创建窗口
    const borderless = config.get().titlebar.custom;
    const window = try Window.create(allocator, image_size, .{ .windowed = true, .mode = .gpu, .borderless = borderless });
    errdefer window.destroy();
    try app_env.trace_mark("Window.create");
    // 获取显示层共享的 GPU 设备
    const device = try Device.getGpu();
    // 绑定窗口到 GPU 设备
    try device.claimWindow(window.sdl_window);
    try app_env.trace_mark("gpu_init");
    window.gpu_device = device;
    // 关闭垂直同步（修改交换链的 Present Mode）
    // 默认的 SDL_GPU_PRESENTMODE_FIFO 有垂直同步效果，会阻塞渲染循环（导致事件积压，延迟响应）
    // 注意：目前垂直同步关闭已被取消，sdl_gpu 仍然是默认状态。
    // if (c.SDL_WindowSupportsGPUPresentMode(gpu.gpu_device, window.sdl_window, c.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
    //     _ = h.check(c.SDL_SetGPUSwapchainParameters( // 忽略返回状态，仅输出错误消息
    //         gpu.gpu_device,
    //         window.sdl_window,
    //         c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
    //         c.SDL_GPU_PRESENTMODE_IMMEDIATE,
    //     ));
    // } else {
    //     std.log.warn("IMMEDIATE Present Mode not supported", .{});
    // }

    // 扫描和加载用户着色器（包括背景）
    var shaders: ?shader.loaded.All = null;
    if (config.get().base_dir) |base_dir| if (shared.pathExists(base_dir)) {
        // 检查着色器目录是否存在
        const full_path = try config.allocFullPath(allocator, config.get().shaders.dir);
        defer allocator.free(full_path);
        if (shared.pathExists(full_path)) {
            std.log.info("Scanning shaders in directory: {s}", .{full_path});
            shaders = try shader.Scanner.loadAll(allocator, device, full_path);
        } else {
            std.log.warn("Shader directory does not exist: {s}", .{full_path});
        }
    };
    try app_env.trace_mark("shaders_loading");

    // 记录图片形状
    app_env.writer().image_shape = image.shape;
    // 创建 ass 渲染器
    const ass_renderer = try ass.Renderer.init(try ui.AssLibrary.get());
    // 设置 ass 渲染器字体
    ass_renderer.setFonts(null, ui.DEFAULT_FONT, ass.c.ASS_FONTPROVIDER_AUTODETECT, null, 1);
    try app_env.trace_mark("ass_init");

    return Self{
        .gpa = allocator,
        .window = window,
        .device = device,
        .shaders = shaders,
        .ass_renderer = ass_renderer,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing GPU mode", .{});
    if (self.shaders) |*shaders| { // 着色器释放时依赖 gpu
        for (shaders.list.items) |item| self.device.releaseGPUShader(item.shader);
        shaders.deinit();
    }
    self.window.destroy();
    self.ass_renderer.deinit("gpu mode");
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    defer Device.discardUploader();
    // 设置 ass 帧尺寸（文字据此相对 PLAY_RES 缩放）
    self.ass_renderer.setFrameSize(self.window.fit_size.w, self.window.fit_size.h);
    const image = try gallery.current();
    // 当来自于模式切换（预览 -> GPU），立即释放内存
    if (app_env.reader().preview_initialized) shared.heap.mallocTrim();
    // UI 组件共享的管线注册表
    try pipelines.registry.init(self.gpa, self.window, self.device);
    defer pipelines.registry.deinit();
    // 更新窗口尺寸
    app_env.writer().image_shape = image.shape;
    try self.window.setTitle(image.file_name, .{
        .include_content_size = !(config.get().titlebar.hidden_file_size),
        .include_app_suffix = !(config.get().titlebar.hidden_app_name),
    });
    self.window.imageSizeUpdated(image.shape.toSize2D(i32));
    self.window.updateFit(); // 窗口状态可能已脏，始终重新计算 fit 尺寸

    // 创建错误横幅
    var error_banner: ui.TextBanner = try .init(self.gpa, &self.ass_renderer, self.window.fit_size, .{});
    defer error_banner.deinit();

    // 顶部标题栏（自带 close / minimize 按钮）
    var title_bar: ?ui.TitleBar = null;
    if (self.window.borderless) {
        const window_size = self.window.fit_size;
        title_bar = try ui.TitleBar.init(self.gpa, window_size, .{
            .color = .rgba(0.0, 0.0, 0.0, config.get().titlebar.opacity),
        });
        title_bar.?.bindEvents(); // 调用绑定不能用临时的栈变量
    }
    defer if (title_bar) |*tb| tb.deinit();

    var widget_count: usize = 0;
    // 组件数量是动态的，预先分配已知上限的数组
    var widgets: [MAX_WIDGETS]ui.Widget = undefined;
    if (title_bar) |*tb| {
        if (!(config.get().titlebar.hidden_all_text)) try tb.setText(self.window.getTitle());
        widgets[widget_count] = tb.toWidget();
        widget_count += 1;
    }

    var deps = try RenderDeps.init(
        self.gpa,
        self.window,
        self.device,
        image,
        self.shaders,
        widgets[0..widget_count],
        &error_banner,
    );
    errdefer deps.deinit();
    try app_env.trace_mark("RenderDeps.init");

    var context = events.Context.init(&deps, &title_bar);
    // 显示窗口
    try self.window.show();
    try app_env.trace_mark("window.show");
    // 启动循环
    const action = try loop.run(&deps, &context);
    // 正常退出时释放本次会话的渲染依赖
    deps.deinit();
    return action;
}
