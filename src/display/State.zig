const std = @import("std");
const c = @import("sdl").c;
const sdl = @import("sdl");
const root = @import("../root.zig");
const shared = @import("shared");
const config = root.config;
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const LImage = @import("vips").LImage;
const IShape = shared.IShape;
const Size2D = shared.Size2D;
const Point = shared.Point(f32);
const Window = @import("window.zig");
const Shaders = std.ArrayList(*c.SDL_GPUShader);
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
window: ?*Window = null,
renderer: ?sdl.Renderer = null,
gpu_window: ?*Window = null,
gpu: ?sdl.Gpu = null,
shaders: ?Shaders = null,
extracted: ?Extractor = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |*renderer| renderer.destroy();
    if (self.window) |window| window.destroy();
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

pub fn getRenderer(self: *Self) Error!*sdl.Renderer {
    return if (self.renderer) |*renderer| renderer else Error.RendererNotCreated;
}

pub fn startRendering(self: *Self, image: *const LImage, mode: Mode) Error!void {
    const image_size = image.shape.toSize2D(i32);
    if (mode == .pewview and self.window == null) {
        const window = try Window.create(
            self.allocator,
            image_size,
            .{ .windowed = false, .mode = mode },
        );
        // 创建 renderer
        var renderer = try sdl.Renderer.create(window.sdl_window);
        errdefer window.destroy();
        // 开启垂直同步
        try renderer.setRenderVSync(1);
        self.window = window;
        self.renderer = renderer;
    } else if (mode == .gpu and self.gpu_window == null) {
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

    if (self.current_mode == .pewview) {
        if (self.window) |window| try window.show();
    } else if (self.current_mode == .gpu) {
        if (self.gpu_window) |window| {
            window.imageSizeUpdated(image_size); // 显示前更新窗口中的图片尺寸
            try window.show();
        }
    }
}

pub fn stopRendering(self: *Self) Error!void {
    if (self.current_mode == .pewview) {
        if (self.window) |w| try w.hide();
    } else if (self.current_mode == .gpu) {
        if (self.gpu_window) |w| try w.hide();
    }
}

pub fn writeTexture(self: *Self, gpu: *sdl.Gpu, gpu_texture: ?*c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, gpu, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}

pub fn readTexture(self: *Self) Error!?*c.SDL_Texture {
    if (self.extracted) |*extracted| {
        defer {
            extracted.deinit(); // 读取后释放下载数据
            self.extracted = null; // 清除缓存，避免 deinit 重复释放
        }
        const pitch = self.image_shape.w * self.image_shape.c; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建图片纹理
        const texture = try self.renderer.?.createTexture(
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            self.image_shape.w,
            self.image_shape.h,
        );
        // 开启纹理混合模式
        try sdl.Renderer.setTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);
        // 上传纹理
        try sdl.Renderer.updateTexture(
            texture,
            null,
            extracted.pixels_slice.ptr,
            pitch,
        );

        return texture;
    }

    return null;
}
