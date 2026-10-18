const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config");
const slang = @import("slang");
const ui = @import("../ui.zig");
const gallery = @import("../gallery.zig");
const Window = @import("window.zig");
const Device = @import("../Device.zig");
const app_env = @import("../app_env.zig");
const shader = @import("../shader.zig");
const RenderDeps = @import("gpu/RenderDeps.zig");
const events = @import("gpu/events.zig");
const Uploader = @import("Uploader.zig");
const Widget = ui.Widget;
const TextPipeline = ui.TextPipeline;
const RectPipeline = ui.RectPipeline;
const TitleBar = ui.TitleBar;
const loop = @import("gpu/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Shaders = std.ArrayList(*sdl.c.SDL_GPUShader);
const Self = @This();

// 组件总量
const MAX_WIDGETS = 1; // 当前仅有 title_bar 组件

allocator: std.mem.Allocator,
window: *Window,
device: *const sdl.Gpu,
shaders: ?Shaders,

pub fn init(allocator: std.mem.Allocator) Error!Self {
    // 初始化 GPU 模式
    std.log.info("Initializing GPU mode", .{});
    const image = try gallery.current();
    const image_size = image.shape.toSize2D(i32);
    // 创建窗口
    const borderless = config.get().titlebar.custom;
    const window = try Window.create(allocator, image_size, .{ .windowed = true, .mode = .gpu, .borderless = borderless });
    errdefer window.destroy();
    // 获取显示层共享的 GPU 设备
    const device = try Device.getGpu();
    // 绑定窗口到 GPU 设备
    try device.claimWindow(window.sdl_window);
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

    // 加载背景着色器
    try shader.Scanner.loadBackground(allocator, device);
    // 扫描并编译用户着色器
    var shaders: ?Shaders = null;
    if (config.get().base_dir) |base_dir| if (shared.pathExists(base_dir)) {
        var sf = std.heap.stackFallback(256, allocator);
        const sfa = sf.get();
        const full_path = try config.allocFullPath(sfa, config.get().shaders.dir);
        defer sfa.free(full_path);
        if (shared.pathExists(full_path)) {
            var shader_scanner = try shader.Scanner.init(allocator, full_path);
            defer shader_scanner.deinit();
            std.log.info("Scanning shaders in directory: {s}", .{full_path});
            try shader_scanner.scan();
            if (shader_scanner.scanner.names.items.len > 0) { // 仅仅在扫描到着色器后才初始化 Slang
                try slang.init();
                shaders = try shader_scanner.compileShaders(allocator, device);
                slang.deinit();
            }
        } else {
            std.log.warn("Shader directory does not exist: {s}", .{full_path});
        }
    };

    // 记录图片形状
    app_env.writer().image_shape = image.shape;

    return Self{
        .allocator = allocator,
        .window = window,
        .device = device,
        .shaders = shaders,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing GPU mode", .{});
    if (self.shaders) |*shaders| { // 着色器释放时依赖 gpu
        for (shaders.items) |s| self.device.releaseGPUShader(s);
        shaders.deinit(self.allocator);
    }
    self.window.destroy();
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    const image = try gallery.current();
    // 当来自于模式切换（预览 -> GPU），立即释放内存
    if (app_env.reader().preview_initialized) shared.heap.mallocTrim();
    const shaders: ?[]const *sdl.c.SDL_GPUShader = if (self.shaders) |*s| s.items else null;
    // 所有组件的资源上传共用同一个上传器，最后由外部统一提交
    var uploader = Uploader.init(self.allocator, self.device);
    defer uploader.deinit();
    // 纯色矩形背景（Button / TitleBar）共享的渲染管线
    var rect_pipeline = try RectPipeline.init(self.window, self.device);
    defer rect_pipeline.deinit();
    // 所有文字/图标组件共享的渲染管线
    var text_pipeline = try TextPipeline.init(self.window, self.device);
    defer text_pipeline.deinit();
    // 更新窗口尺寸
    app_env.writer().image_shape = image.shape;
    try self.window.setTitle(image.file_name, .{
        .include_content_size = !(config.get().titlebar.no_size orelse false),
        .include_app_suffix = !(config.get().titlebar.no_app orelse false),
    });
    self.window.imageSizeUpdated(image.shape.toSize2D(i32));
    self.window.updateFit(); // 窗口状态可能已脏，始终重新计算 fit 尺寸
    // 顶部标题栏（自带 close / minimize 按钮）
    var title_bar: ?TitleBar = null;
    if (self.window.borderless) {
        const window_size = self.window.fit_size;
        title_bar = try TitleBar.init(self.allocator, &uploader, &text_pipeline, &rect_pipeline, window_size, .{
            .color = .rgba(0.0, 0.0, 0.0, config.get().titlebar.opacity orelse 0.25),
        });
        title_bar.?.bindEvents(); // 调用绑定不能用临时的栈变量
    }
    defer if (title_bar) |*tb| tb.deinit();

    var widget_count: usize = 0;
    // 组件数量是动态的，预先分配已知上限的数组
    var widgets: [MAX_WIDGETS]Widget = undefined;
    if (title_bar) |*tb| {
        if (!(config.get().titlebar.no_text orelse false)) try tb.setText(self.window.getTitle());
        widgets[widget_count] = tb.toWidget();
        widget_count += 1;
    }

    try uploader.submit();

    var deps = try RenderDeps.init(
        self.allocator,
        self.window,
        self.device,
        shaders,
        image,
        widgets[0..widget_count],
    );
    errdefer deps.deinit();

    var context = events.Context.init(&deps, &title_bar);
    // 显示窗口
    try self.window.show();
    // 启动循环
    const action = try loop.run(&deps, &context);
    // 正常退出时释放本次会话的渲染依赖
    deps.deinit();
    return action;
}
