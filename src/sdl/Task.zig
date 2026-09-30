const std = @import("std");
const c = @import("c.zig").c;
const atomic = std.atomic;
const gpu = @import("gpu.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const loader = @import("../vips/loader.zig");
const Size = @import("structs.zig").Size(u32);
const Image = @import("../vips.zig").Image;
const RenderState = @import("State.zig");
const Extractor = @import("Extractor.zig");
const Self = @This();

const State = enum(u8) { running, done, failed };
const Result = struct {
    width: u32,
    height: u32,
    data_ptr: *anyopaque,
    _out: Image.Out,

    pub fn deinit(self: *Result) void {
        self._out.deinit();
    }
};

allocator: Allocator,
state: atomic.Value(State) = .init(.running),
thread: std.Thread = undefined,
extracted: ?Extractor = null,
result: ?Result = null,

pub fn start(
    allocator: Allocator,
    device: *c.SDL_GPUDevice,
    texture: ?*c.SDL_GPUTexture,
    width: i32,
    height: i32,
    bands: i32,
    render_state: *RenderState,
) Error!*Self {
    const self_ptr = try allocator.create(Self);
    errdefer allocator.destroy(self_ptr);

    self_ptr.* = .{
        .allocator = allocator,
        .thread = try std.Thread.spawn(.{}, run, .{ self_ptr, device, texture, width, height, bands, render_state }),
    };
    return self_ptr;
}

fn run(
    self: *Self,
    device: *c.SDL_GPUDevice,
    texture: ?*c.SDL_GPUTexture,
    width: i32,
    height: i32,
    bands: i32,
    render_state: *RenderState,
) !void {
    std.log.debug("bands: {d}", .{bands});
    std.log.info("Task is running", .{});
    // 创建提取器
    self.extracted = try Extractor.extract(self.allocator, device, texture, width, height, bands);
    // 初始化模型
    try render_state.initBirefnet();
    const data_ptr = self.extracted.?.pixels_slice.ptr;
    // 运行模型推理
    var image = try render_state.birefnet.?.run(
        self.allocator,
        .{ .data_ptr = data_ptr, .width = @intCast(width), .height = @intCast(height), .bands = @intCast(bands) },
    );
    defer image.deinit();
    const out = try image.allocOutInMemory();
    self.result = Result{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data_ptr = out.data_ptr,
        ._out = out,
    };
    self.state.store(.done, .release);
}

pub fn poll(self: *Self) State {
    return self.state.load(.acquire);
}

pub fn finish(self: *Self) void {
    self.thread.detach();
    if (self.result) |*r| r.deinit();
    if (self.extracted) |*e| e.deinit();
    self.allocator.destroy(self);
}
