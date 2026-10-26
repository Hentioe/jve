const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Environ = std.process.Environ;
const IShape = shared.IShape;
const Point = shared.Point(f32);
const extractor = @import("extractor.zig");
const StepTrace = @import("StepTrace.zig");
const Self = @This();

pub const Error = sdl.Error || std.mem.Allocator.Error || StepTrace.Error;

// 应用唯一的全局数据缓存，由 root 在初始化/反初始化时管理生命周期。
// 不持有显示相关的资源（Viewer、GPU 设备、窗口等），因此释放顺序无强依赖。
var instance: Self = undefined;
var initialized: bool = false;

fn fatalMutexIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

environ_map: ?*const Environ.Map,
trace: ?*StepTrace,
image_shape: IShape(i32) = undefined,
target_angle: f64 = 0.0,
target_scale: f64 = 1.0,
move_offset: Point = .{},
preview_initialized: bool = false,
window_dirty: bool = false, // 窗口状态已脏（如预览模式轮换）
fatal_mutex: std.Io.Mutex = .init,
fatal_slot: ?shared.Fatal = null,
extracted: ?extractor.Extracted = null, // 已提取的纹理（模式切换时复用）

pub const InitOptions = struct {
    environ_map: ?*const Environ.Map = null,
    trace: ?*StepTrace = null,
};

pub fn init(options: InitOptions) void {
    if (initialized) return;
    instance = Self{
        .environ_map = options.environ_map,
        .trace = options.trace,
    };
    initialized = true;
}

pub fn deinit() void {
    if (!initialized) return;
    if (instance.extracted) |*extracted| extracted.deinit();
    instance = undefined;
    initialized = false;
}

pub inline fn traceMark(step: []const u8) void {
    if (instance.trace) |t| t.markBounded(step);
}

pub inline fn traceComplete() void {
    if (instance.trace) |t| t.complete();
}

// 只读访问
pub fn reader() *const Self {
    return &instance;
}

// 可变访问
pub fn writer() *Self {
    return &instance;
}

pub fn getEnvVar(self: *const Self, name: []const u8) ?[]const u8 {
    const map = self.environ_map orelse @panic("environment map not initialized");
    return map.get(name);
}

pub fn getEnvVarOwned(self: *const Self, allocator: Allocator, name: []const u8) error{OutOfMemory}!?[]u8 {
    if (self.getEnvVar(name)) |val| {
        return try allocator.dupe(u8, val);
    } else {
        return null;
    }
}

pub fn report(err: anytype, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) @TypeOf(err) {
    instance.fatal_mutex.lockUncancelable(fatalMutexIo());
    defer instance.fatal_mutex.unlock(fatalMutexIo());
    if (instance.fatal_slot != null) return err; // 只保留第一个

    var f: shared.Fatal = .{ .err = err, .src = src };
    const s = std.fmt.bufPrint(&f.msg_buf, fmt, args) catch blk: {
        const t = "message too long";
        @memcpy(f.msg_buf[0..t.len], t);
        break :blk f.msg_buf[0..t.len];
    };
    f.msg_len = s.len;
    instance.fatal_slot = f;
    return err;
}

/// 顶层兜底：如果还没人记录，就至少记下错误名
pub fn ensureFatal(err: anyerror) void {
    instance.fatal_mutex.lockUncancelable(fatalMutexIo());
    defer instance.fatal_mutex.unlock(fatalMutexIo());
    if (instance.fatal_slot == null) {
        var f: shared.Fatal = .{ .err = err, .src = @src() };
        const s = std.fmt.bufPrint(&f.msg_buf, "{s}", .{@errorName(err)}) catch unreachable;
        f.msg_len = s.len;
        instance.fatal_slot = f;
    }
}

/// 诊断模式调用：取出并清空
pub fn takeFatal(self: *Self) ?shared.Fatal {
    self.fatal_mutex.lockUncancelable(fatalMutexIo());
    defer self.fatal_mutex.unlock(fatalMutexIo());
    if (self.fatal_slot) |slot| {
        self.fatal_slot = null;
        return slot;
    }
    return null;
}

/// 提取并缓存纹理像素
pub fn writeTexture(self: *Self, allocator: Allocator, device: *const sdl.Gpu, gpu_texture: ?*sdl.c.SDL_GPUTexture) Error!void {
    self.extracted = try extractor.extract(
        allocator,
        device,
        gpu_texture,
        self.image_shape.to(u32),
    );
}

/// 读取像素缓存，创建纹理（模式切换返回预览时复用）
pub fn readTexture(self: *Self, renderer: *sdl.Renderer) Error!?*sdl.Texture {
    if (self.extracted) |*extracted| {
        defer {
            extracted.deinit(); // 读取后释放已提取数据
            self.extracted = null; // 避免 deinit 重复释放
        }
        const data_prt = extracted.data.ptr;
        const shape = self.image_shape;
        const pitch = shape.w * shape.c; // 计算 pitch
        std.log.info("Pitch: {d}", .{pitch});
        // 创建纹理
        const texture = try renderer.createTexture(
            sdl.c.SDL_PIXELFORMAT_RGBA32,
            sdl.c.SDL_TEXTUREACCESS_STATIC,
            shape.w,
            shape.h,
        );
        // 开启纹理混合模式
        try sdl.Renderer.setTextureBlendMode(texture, sdl.c.SDL_BLENDMODE_BLEND);
        // 上传纹理
        try sdl.Renderer.updateTexture(texture, null, data_prt, pitch);

        return texture;
    }

    return null;
}
