const std = @import("std");
const ort = @import("ort");
const enums = @import("enums.zig");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const root = @import("../root.zig");
const config = root.config;
const Api = ort.Api;
const Allocator = std.mem.Allocator;
const RwLock = std.Thread.RwLock;
const Error = @import("errors.zig").Error;
const LImage = root.loader.LoadedImage;
const IShape = root.IShape;
const Point = root.Point(f32);
const Window = @import("window.zig");
const Shaders = std.ArrayList(*c.SDL_GPUShader);
const Backend = @import("enums.zig").Backend;
const Extractor = @import("Extractor.zig");
const ShaderScanner = @import("ShaderScanner.zig");
const BiRefNet = @import("../models/BiRefNet.zig");
const MagicTouch = @import("../models/MagicTouch.zig");
const Self = @This();

pub const Model = enum { BiRefNet, MagicTouch };

allocator: Allocator,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
current_backend: Backend = undefined,
window: ?*Window = null,
renderer: ?*c.SDL_Renderer = null,
gpu_window: ?*Window = null,
gpu_device: ?*c.SDL_GPUDevice = null,
shaders: ?Shaders = null,
extracted: ?Extractor = null,
ort_lock: RwLock = .{},
ort_api: ?ort.Api = null,
birefnet: ?BiRefNet = null,
magick_touch: ?MagicTouch = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{ .allocator = allocator };
}

pub fn initModel(self: *Self, model: Model) Error!void {
    self.ort_lock.lock();
    defer self.ort_lock.unlock();
    if (self.ort_api == null) {
        self.ort_api = try Api.init(self.allocator, "jve");
    }
    switch (model) {
        .BiRefNet => {
            if (self.birefnet == null) {
                self.birefnet = try BiRefNet.init(&self.ort_api.?);
            }
        },
        .MagicTouch => {
            if (self.magick_touch == null) {
                self.magick_touch = try MagicTouch.init(&self.ort_api.?);
            }
        },
    }
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |renderer| c.SDL_DestroyRenderer(renderer);
    if (self.window) |window| window.destroy();
    if (self.shaders) |*shaders| { // 着色器释放时依赖 gpu_device
        for (shaders.items) |shader| c.SDL_ReleaseGPUShader(self.gpu_device, shader);
        shaders.deinit(self.allocator);
    }
    if (self.gpu_device) |device| c.SDL_DestroyGPUDevice(device);
    if (self.gpu_window) |window| window.destroy();
    if (self.extracted) |*extractor| extractor.deinit();
    if (self.birefnet) |*birefnet| birefnet.deinit();
    if (self.ort_api) |*ort_api| ort_api.deinit();
    self.* = undefined;
}

pub fn startRendering(self: *Self, image: *const LImage, backend: Backend) Error!void {
    const image_size = image.shape.toISize(i32);
    if (backend == .sdl_renderer and self.window == null) {
        const window = try Window.create(
            self.allocator,
            image_size,
            .{ .windowed = false, .backend = backend },
        );
        const renderer = c.SDL_CreateRenderer(window.sdl_window, null) orelse {
            h.printError();
            return Error.SdlCreateRendererFailed;
        };
        // 开启垂直同步
        if (!h.check(c.SDL_SetRenderVSync(renderer, 1))) return Error.SdlSetRenderVSyncFailed;
        self.window = window;
        self.renderer = renderer;
    } else if (backend == .sdl_gpu and self.gpu_window == null) {
        // 正在初始化 SDL GPU 后端
        std.log.info("Initializing SDL GPU backend", .{});
        // 创建窗口
        const window = try Window.create(
            self.allocator,
            image_size,
            .{ .backend = .sdl_gpu },
        );
        // 创建 GPU 设备
        const device = c.SDL_CreateGPUDevice(
            c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL,
            false,
            null,
        ) orelse {
            h.printError();
            return Error.SdlCreateGPUDeviceFailed;
        };
        // 绑定窗口到 GPU 设备
        if (!h.check(c.SDL_ClaimWindowForGPUDevice(device, window.sdl_window))) return Error.SdlClaimWindowForGPUDeviceFailed;
        // 关闭垂直同步（修改交换链的 Present Mode）
        // 默认的 SDL_GPU_PRESENTMODE_FIFO 有垂直同步效果，会阻塞渲染循环（导致事件积压，延迟响应）
        // 注意：目前垂直同步关闭已被取消，sdl_gpu 仍然是默认状态。
        // if (c.SDL_WindowSupportsGPUPresentMode(device, window.sdl_window, c.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
        //     _ = h.check(c.SDL_SetGPUSwapchainParameters( // 忽略返回状态，仅输出错误消息
        //         device,
        //         window.sdl_window,
        //         c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        //         c.SDL_GPU_PRESENTMODE_IMMEDIATE,
        //     ));
        // } else {
        //     std.log.warn("IMMEDIATE Present Mode not supported", .{});
        // }

        // 扫描和编译着色器
        if (config.get().shader_dir) |dir| {
            var shader_scanner = try ShaderScanner.init(self.allocator, dir);
            defer shader_scanner.deinit();
            std.log.info("Scanning shaders in directory: {s}", .{dir});
            try shader_scanner.scan();
            self.shaders = try shader_scanner.compileShaders(self.allocator, device);
        }

        self.gpu_window = window;
        self.gpu_device = device;
    }
    self.image_shape = image.shape;
    self.current_backend = backend;

    if (self.current_backend == .sdl_renderer) {
        if (self.window) |window| try window.show();
    } else if (self.current_backend == .sdl_gpu) {
        if (self.gpu_window) |window| {
            window.imageSizeUpdated(image_size); // 显示前更新窗口中的图片尺寸
            try window.show();
        }
    }
}

pub fn stopRendering(self: *Self) Error!void {
    if (self.current_backend == .sdl_renderer) {
        if (self.window) |w| try w.hide();
    } else if (self.current_backend == .sdl_gpu) {
        if (self.gpu_window) |w| try w.hide();
    }
}

pub fn writeTexture(self: *Self, device: *c.SDL_GPUDevice, gpu_texture: ?*c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, device, self.image_shape);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}

pub fn readTexture(self: *Self, renderer: *c.SDL_Renderer) Error!?*c.SDL_Texture {
    if (self.extracted) |*extracted| {
        defer {
            extracted.deinit(); // 读取后释放下载数据
            self.extracted = null; // 清除缓存，避免 deinit 重复释放
        }
        const pitch = self.image_shape.w * self.image_shape.c; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建图片纹理
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            self.image_shape.w,
            self.image_shape.h,
        );
        if (texture == null) {
            h.printError();
            return Error.SdlCreateTextureFailed;
        }
        // 开启纹理混合模式
        if (!h.check(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND))) return Error.SdlSetTextureBlendModeFailed;
        // 上传纹理
        if (!h.check(c.SDL_UpdateTexture(
            texture,
            null,
            extracted.pixels_slice.ptr,
            pitch,
        ))) return Error.SdlUpdateTextureFailed;

        return texture;
    }

    return null;
}
