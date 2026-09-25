const std = @import("std");
const ort = @import("ort");
const enums = @import("enums.zig");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const structs = @import("structs.zig");
const Api = ort.Api;
const Allocator = std.mem.Allocator;
const RwLock = std.Thread.RwLock;
const Error = @import("errors.zig").Error;
const Image = @import("../root.zig").loader.Image;
const Size = @import("structs.zig").Size(i32);
const Window = @import("window.zig");
const Backend = @import("enums.zig").Backend;
const Point = structs.Point;
const Extractor = @import("Extractor.zig");
const BiRefNet = @import("../models/BiRefNet.zig");
const Self = @This();

allocator: Allocator,
size: Size,
bands: i32,
target_angle: f32 = 0.0,
target_scale: f32 = 1.0,
movement_offset: Point = .{},
current_backend: Backend = undefined,
window: ?*Window = null,
renderer: ?*c.SDL_Renderer = null,
gpu_window: ?*Window = null,
gpu_device: ?*c.SDL_GPUDevice = null,
extracted: ?Extractor = null,
ort_lock: RwLock = .{},
ort_api: ?ort.Api = null,
birefnet: ?BiRefNet = null,

pub fn init(allocator: Allocator) Error!Self {
    return Self{
        .allocator = allocator,
        .size = .{ .w = 0, .h = 0 },
        .bands = 0,
    };
}

pub fn initBirefnet(self: *Self) Error!void {
    self.ort_lock.lock();
    if (self.ort_api == null) {
        self.ort_api = try Api.init(self.allocator, "imageviewer");
    }
    if (self.birefnet == null) {
        self.birefnet = try BiRefNet.init(&self.ort_api.?, .lite);
    }
    self.ort_lock.unlock();
}

pub fn deinit(self: *Self) void {
    if (self.renderer) |renderer| c.SDL_DestroyRenderer(renderer);
    if (self.window) |window| window.destroy();
    if (self.gpu_device) |device| c.SDL_DestroyGPUDevice(device);
    if (self.gpu_window) |window| window.destroy();
    if (self.extracted) |*extractor| extractor.deinit();
    if (self.birefnet) |*birefnet| birefnet.deinit();
    if (self.ort_api) |*ort_api| ort_api.deinit();
    self.* = undefined;
}

pub fn startRendering(self: *Self, image: *const Image, backend: Backend) Error!void {
    if (backend == .sdl_renderer and self.window == null) {
        const window = try Window.create(
            self.allocator,
            image.width,
            image.height,
            .{ .has_border = false, .backend = backend },
        );
        const renderer = c.SDL_CreateRenderer(window.sdl_window, null) orelse {
            h.printError();
            return Error.SdlCreateRendererFailed;
        };
        self.window = window;
        self.renderer = renderer;
    } else if (backend == .sdl_gpu and self.gpu_window == null) {
        // 正在初始化 SDL GPU 后端
        std.log.info("Initializing SDL GPU backend", .{});
        // 创建窗口
        const window = try Window.create(
            self.allocator,
            image.width,
            image.height,
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
        _ = h.check(c.SDL_ClaimWindowForGPUDevice(device, window.sdl_window)) or return Error.SdlClaimWindowForGPUDeviceFailed;
        // 关闭垂直同步（修改交换链的 Present Mode）
        // 默认的 SDL_GPU_PRESENTMODE_FIFO 有垂直同步效果，会阻塞渲染循环（导致事件积压，延迟响应）
        if (c.SDL_WindowSupportsGPUPresentMode(device, window.sdl_window, c.SDL_GPU_PRESENTMODE_IMMEDIATE)) {
            _ = h.check(c.SDL_SetGPUSwapchainParameters( // 此处忽略返回状态（仅输出错误消息）
                device,
                window.sdl_window,
                c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
                c.SDL_GPU_PRESENTMODE_IMMEDIATE,
            ));
        } else {
            std.log.warn("IMMEDIATE Present Mode not supported", .{});
        }

        self.gpu_window = window;
        self.gpu_device = device;
    }
    self.size = .{ .w = image.width, .h = image.height };
    self.bands = image.bands;
    self.current_backend = backend;

    if (self.current_backend == .sdl_renderer) {
        if (self.window) |w| w.show();
    } else if (self.current_backend == .sdl_gpu) {
        if (self.gpu_window) |w| w.show();
    }
}

pub fn stopRendering(self: *Self) void {
    if (self.current_backend == .sdl_renderer) {
        if (self.window) |w| w.hide();
    } else if (self.current_backend == .sdl_gpu) {
        if (self.gpu_window) |w| w.hide();
    }
}

pub fn writeTexture(self: *Self, device: *c.SDL_GPUDevice, gpu_texture: ?*c.SDL_GPUTexture) Error!void {
    // 创建提取器
    var extracted = Extractor.init(self.allocator, device, self.size.w, self.size.h, self.bands);
    // 下载纹理
    try extracted.downloadTexture(gpu_texture);
    // 缓存已下载的内容
    self.extracted = extracted;
}

pub fn readTexture(self: *Self, renderer: *c.SDL_Renderer) Error!?*c.SDL_Texture {
    if (self.extracted) |*extracted| {
        defer extracted.deinit(); // 读取后释放下载数据
        const pitch = self.size.w * self.bands; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建图片纹理
        const texture = c.SDL_CreateTexture(
            renderer,
            c.SDL_PIXELFORMAT_RGBA32,
            c.SDL_TEXTUREACCESS_STATIC,
            self.size.w,
            self.size.h,
        );
        if (texture == null) {
            h.printError();
            return Error.SdlCreateTextureFailed;
        }
        // 开启纹理混合模式
        _ = h.check(c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND)) or return Error.SdlSetTextureBlendModeFailed;
        // 上传纹理
        _ = h.check(c.SDL_UpdateTexture(
            texture,
            null,
            extracted.pixels_slice.ptr,
            pitch,
        )) or return Error.SdlUpdateTextureFailed;

        return texture;
    } else {
        return null;
    }
}
