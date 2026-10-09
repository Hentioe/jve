const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const LImage = @import("vips").LImage;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const Window = @import("window.zig");
const Preview = @import("Preview.zig");
const Shaders = std.ArrayList(*sdl.c.SDL_GPUShader);
const Mode = @import("enums.zig").Mode;
const Extractor = @import("Extractor.zig");
const ShaderScanner = @import("ShaderScanner.zig");
const Self = @This();

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
current_mode: Mode = undefined,
preview: ?Preview = null,
gpu_window: ?*Window = null,
gpu: ?sdl.Gpu = null,
shaders: ?Shaders = null,
extracted: ?Extractor = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    if (self.preview) |*preview| preview.deinit();
    if (self.shaders) |*shaders| { // 着色器释放时依赖 gpu
        if (self.gpu) |*gpu| for (shaders.items) |shader| gpu.releaseGPUShader(shader);
        shaders.deinit(self.allocator);
    }
    if (self.gpu) |*gpu| gpu.destroy();
    if (self.gpu_window) |window| window.destroy();
    if (self.extracted) |*extractor| extractor.deinit();
    self.* = undefined;
}

pub fn getGpu(self: *Self) Error!*sdl.Gpu {
    return if (self.gpu) |*gpu| gpu else Error.GpuNotCreated;
}

pub fn startRendering(self: *Self, image: *const LImage, mode: Mode) Error!void {
    const image_size = image.shape.toSize2D(i32);
    if (mode == .gpu and self.gpu_window == null) {
        // 正在初始化 SDL GPU 后端
        std.log.info("Initializing SDL GPU mode", .{});
        // 创建窗口
        const window = try Window.create(
            self.allocator,
            image_size,
            .{ .windowed = true, .mode = .gpu },
        );
        errdefer window.destroy();
        // 创建 GPU
        var gpu = try sdl.Gpu.create();
        errdefer gpu.destroy();
        // 绑定窗口到 GPU 设备
        try gpu.claimWindow(window.sdl_window);
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
        if (config.get().base_dir) |base_dir| if (shared.pathExists(base_dir)) {
            var sf = std.heap.stackFallback(256, self.allocator);
            const sfa = sf.get();
            const full_path = try config.allocFullPath(sfa, config.get().shaders.dir);
            defer sfa.free(full_path);
            if (shared.pathExists(full_path)) {
                var shader_scanner = try ShaderScanner.init(self.allocator, full_path);
                defer shader_scanner.deinit();
                std.log.info("Scanning shaders in directory: {s}", .{full_path});
                try shader_scanner.scan();
                self.shaders = try shader_scanner.compileShaders(self.allocator, &gpu);
            } else {
                std.log.warn("Shader directory does not exist: {s}", .{full_path});
            }
        };

        self.gpu_window = window;
        self.gpu = gpu;
    }
    self.image_shape = image.shape;
    self.current_mode = mode;

    if (self.current_mode == .gpu) {
        if (self.gpu_window) |window| {
            window.imageSizeUpdated(image_size); // 显示前更新窗口中的图片尺寸
            try window.show();
        }
    }
}

pub fn stopRendering(self: *Self) Error!void {
    if (self.current_mode == .gpu) {
        if (self.gpu_window) |w| try w.hide();
    }
}

pub fn writeTexture(self: *Self, gpu: *sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, gpu, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}
