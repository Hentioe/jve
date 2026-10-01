const std = @import("std");
const c = @import("c.zig").c;
const atomic = std.atomic;
const gpu = @import("gpu.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const loader = @import("../vips/loader.zig");
const structs = @import("structs.zig");
const Size = structs.Size(u32);
const Point = structs.Point;
const Image = @import("../vips.zig").Image;
const RenderState = @import("State.zig");
const Extractor = @import("Extractor.zig");
const Position = @import("../models/Position.zig");
const ModelInput = @import("../models/processors/Input.zig");
const Self = @This();

const Input = struct {
    width: i32,
    height: i32,
    bands: i32,
    click: ?Point = null,
};
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
    render_state: *RenderState,
    input: Input,
) Error!*Self {
    const self_ptr = try allocator.create(Self);
    errdefer allocator.destroy(self_ptr);

    self_ptr.* = .{
        .allocator = allocator,
        .thread = try std.Thread.spawn(.{}, run, .{ self_ptr, device, texture, render_state, input }),
    };
    return self_ptr;
}

fn run(
    self: *Self,
    device: *c.SDL_GPUDevice,
    texture: ?*c.SDL_GPUTexture,
    render_state: *RenderState,
    input: Input,
) !void {
    std.log.info("Task is running", .{});
    // 提取像素数据
    self.extracted = try Extractor.extract(self.allocator, device, texture, input.width, input.height, input.bands);
    // 初始化模型
    // 如果存在点击座标，则用 MagicTouch 否则用 BiRefNet
    const model: RenderState.Model = if (input.click != null) .MagicTouch else .BiRefNet;
    try render_state.initModel(model);
    const data_ptr = self.extracted.?.pixels_slice.ptr;
    const u_width: u32 = @intCast(input.width);
    const u_height: u32 = @intCast(input.height);
    const u_bands: u32 = @intCast(input.bands);
    const click_position: ?Position = if (input.click) |click| .{ .x = click.x, .y = click.y } else null;
    // 运行模型推理
    var image: Image = undefined;
    const model_input: ModelInput = .{
        .data_ptr = data_ptr,
        .width = u_width,
        .height = u_height,
        .bands = u_bands,
        .click_position = click_position,
    };
    switch (model) {
        .BiRefNet => {
            image = try render_state.birefnet.?.run(self.allocator, model_input);
        },
        .MagicTouch => {
            image = try render_state.magick_touch.?.run(self.allocator, model_input);
        },
    }

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
