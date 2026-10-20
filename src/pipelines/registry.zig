const std = @import("std");
const sdl = @import("sdl");
const c = sdl.c;
const Allocator = std.mem.Allocator;
const Window = @import("../display/window.zig");
const shader_loader = @import("../shader.zig").loader;
const TextPipeline = @import("TextPipeline.zig");
const BannerPipeline = @import("BannerPipeline.zig");
const RectPipeline = @import("RectPipeline.zig");
const Self = @This();

pub const Error = @import("errors.zig").Error;

/// UI 管线的标识。当前每种管线只存在一个实例；若将来某类管线需要按参数
/// 创建多个实例，可在此扩展为 tagged union。
pub const Key = enum {
    text,
    banner,
    rect,
};

/// 类型擦除后的管线句柄，仅用于统一销毁。
pub const Pipeline = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        destroy: *const fn (*anyopaque, Allocator) void,

        pub fn of(comptime T: type) *const VTable {
            const gen = struct {
                fn _destroy(ctx: *anyopaque, allocator: Allocator) void {
                    const self: *T = @ptrCast(@alignCast(ctx));
                    self.deinit();
                    allocator.destroy(self);
                }

                const vtable: VTable = .{ .destroy = _destroy }; // 前缀 `_` 避免歧义引用
            };

            return &gen.vtable;
        }
    };
};

const Entry = struct {
    key: Key,
    pipeline: Pipeline,
};

/// 会话级 UI 管线注册表。由显示模式在 show 期间初始化，所有 UI 组件从中
/// 按需获取管线；show 结束时统一销毁。
var instance: ?Self = null;

allocator: Allocator,
window: *const Window,
gpu: *const sdl.Gpu,
/// 三个 UI 管线共享的顶点着色器，仅在首次取管线时加载。
base_vert: ?*c.SDL_GPUShader = null,
entries: std.ArrayListUnmanaged(Entry) = .empty,

pub fn init(allocator: Allocator, window: *const Window, gpu: *const sdl.Gpu) Error!void {
    std.debug.assert(instance == null);
    instance = .{
        .allocator = allocator,
        .window = window,
        .gpu = gpu,
    };
}

pub fn deinit() void {
    if (instance) |*self| {
        // 先销毁管线，再释放被它们借用的共享顶点着色器。
        var i = self.entries.items.len;
        while (i > 0) {
            i -= 1;
            const entry = self.entries.items[i];
            entry.pipeline.vtable.destroy(entry.pipeline.ptr, self.allocator);
        }
        self.entries.deinit(self.allocator);
        self.gpu.releaseGPUShader(self.base_vert);
        instance = null;
    }
}

/// 文字/图标管线（所有 Text、Icon 共用）。
pub fn text() Error!*TextPipeline {
    const self = try current();
    if (self.find(.text)) |handle| return @ptrCast(@alignCast(handle.ptr));

    const ptr = try self.allocator.create(TextPipeline);
    errdefer self.allocator.destroy(ptr);
    ptr.* = try TextPipeline.init(self.window, self.gpu, try self.baseVert());
    errdefer ptr.deinit();
    try self.register(.text, ptr, TextPipeline);
    return ptr;
}

/// 横幅背景管线（所有 TextBanner 共用）。
pub fn banner() Error!*BannerPipeline {
    const self = try current();
    if (self.find(.banner)) |handle| return @ptrCast(@alignCast(handle.ptr));

    const ptr = try self.allocator.create(BannerPipeline);
    errdefer self.allocator.destroy(ptr);
    ptr.* = try BannerPipeline.init(self.window, self.gpu, try self.baseVert());
    errdefer ptr.deinit();
    try self.register(.banner, ptr, BannerPipeline);
    return ptr;
}

/// 纯色矩形背景管线（Button、TitleBar 共用）。
pub fn rect() Error!*RectPipeline {
    const self = try current();
    if (self.find(.rect)) |handle| return @ptrCast(@alignCast(handle.ptr));

    const ptr = try self.allocator.create(RectPipeline);
    errdefer self.allocator.destroy(ptr);
    ptr.* = try RectPipeline.init(self.window, self.gpu, try self.baseVert());
    errdefer ptr.deinit();
    try self.register(.rect, ptr, RectPipeline);
    return ptr;
}

fn current() Error!*Self {
    if (instance) |*self| return self;
    return error.PipelineRegistryNotInitialized;
}

fn find(self: *Self, key: Key) ?*Pipeline {
    for (self.entries.items) |*entry| {
        if (entry.key == key) return &entry.pipeline;
    }
    return null;
}

fn register(self: *Self, key: Key, ptr: anytype, comptime T: type) Allocator.Error!void {
    try self.entries.append(self.allocator, .{
        .key = key,
        .pipeline = .{
            .ptr = @ptrCast(ptr),
            .vtable = Pipeline.VTable.of(T),
        },
    });
}

fn baseVert(self: *Self) Error!*c.SDL_GPUShader {
    if (self.base_vert) |shader| return shader;
    const shader = try shader_loader.load(self.gpu, @embedFile("base.vert.spv"), "main", .vertex, .{ .samplers = 0, .buffers = 0 });
    self.base_vert = shader;
    return shader;
}
