const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config");
const gallery = @import("../gallery.zig");
const Window = @import("window.zig");
const State = @import("State.zig");
const ShaderScanner = @import("ShaderScanner.zig");
const RenderDeps = @import("gpu/RenderDeps.zig");
const loop = @import("gpu/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Shaders = std.ArrayList(*sdl.c.SDL_GPUShader);
const Self = @This();

allocator: std.mem.Allocator,
window: *Window,
device: sdl.Gpu,
shaders: ?Shaders,
external_state: *State,

pub fn init(allocator: std.mem.Allocator, external_state: *State) Error!Self {
    // 初始化 GPU 模式
    std.log.info("Initializing GPU mode", .{});
    const image = try gallery.current();
    const image_size = image.shape.toSize2D(i32);
    // 创建窗口
    const window = try Window.create(
        allocator,
        image_size,
        .{ .windowed = true, .mode = .gpu },
    );
    errdefer window.destroy();
    // 创建 GPU
    var device = try sdl.Gpu.create();
    errdefer device.destroy();
    // 绑定窗口到 GPU 设备
    try device.claimWindow(window.sdl_window);
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

    // 扫描和编译着色器
    var shaders: ?Shaders = null;
    if (config.get().base_dir) |base_dir| if (shared.pathExists(base_dir)) {
        var sf = std.heap.stackFallback(256, allocator);
        const sfa = sf.get();
        const full_path = try config.allocFullPath(sfa, config.get().shaders.dir);
        defer sfa.free(full_path);
        if (shared.pathExists(full_path)) {
            var shader_scanner = try ShaderScanner.init(allocator, full_path);
            defer shader_scanner.deinit();
            std.log.info("Scanning shaders in directory: {s}", .{full_path});
            try shader_scanner.scan();
            shaders = try shader_scanner.compileShaders(allocator, &device);
        } else {
            std.log.warn("Shader directory does not exist: {s}", .{full_path});
        }
    };

    // 记录外部状态
    external_state.image_shape = image.shape;

    return Self{
        .allocator = allocator,
        .window = window,
        .device = device,
        .shaders = shaders,
        .external_state = external_state,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing GPU mode", .{});
    if (self.shaders) |*shaders| { // 着色器释放时依赖 gpu
        for (shaders.items) |shader| self.device.releaseGPUShader(shader);
        shaders.deinit(self.allocator);
    }
    self.device.destroy();
    self.window.destroy();
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    const image = try gallery.current();
    // 当来自于模式切换（预览 -> GPU），立即释放内存
    if (self.external_state.has(.preview)) shared.heap.mallocTrim();
    const shaders: ?[]const *sdl.c.SDL_GPUShader = if (self.shaders) |*s| s.items else null;
    var deps = try RenderDeps.init(self.allocator, self.window, &self.device, self.external_state, shaders, image);
    errdefer deps.deinit();

    // 更新外部状态与窗口
    self.external_state.image_shape = image.shape;
    try self.window.setTitle(image.file_name);
    self.window.imageSizeUpdated(image.shape.toSize2D(i32));
    try self.window.show();

    const action = try loop.run(&deps);
    // 正常退出时释放本次会话的渲染依赖
    deps.deinit();
    return action;
}
