const std = @import("std");
const c = @import("c.zig").c;
const root = @import("../root.zig");
const shared = @import("shared");
const atomic = std.atomic;
const gpu = @import("gpu.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const loader = @import("../vips/loader.zig");
const IShape = shared.IShape;
const ISize = shared.ISize(u32);
const Point = shared.Point(f32);
const Image = @import("../vips.zig").Image;
const Extractor = @import("Extractor.zig");
const RunnerInput = @import("../ai/processors/Input.zig");
const OrtRunner = @import("../ai/OrtRunner.zig");
const remover = @import("../ai/remover.zig");
const Self = @This();

const Input = struct { shape: IShape(i32), click: ?Point = null };
const State = enum(u8) { running, done };
const Result = union(enum) {
    success: Success,
    failure: anyerror,

    const Success = struct {
        width: u32,
        height: u32,
        data_ptr: *anyopaque,
        _out: Image.Out,

        pub fn deinit(self: *Success) void {
            self._out.deinit();
        }
    };

    pub fn deinit(self: *Result) void {
        switch (self.*) {
            .success => |*s| s.deinit(),
            .failure => {},
        }
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
    input: Input,
) Error!*Self {
    // 申请内存分配自身
    const self_ptr = try allocator.create(Self);
    errdefer allocator.destroy(self_ptr);

    self_ptr.* = .{
        .allocator = allocator,
        .thread = try std.Thread.spawn(.{}, run, .{ self_ptr, device, texture, input }),
    };
    // 返回自身指针
    return self_ptr;
}

fn run(
    self: *Self,
    device: *c.SDL_GPUDevice,
    texture: ?*c.SDL_GPUTexture,
    input: Input,
) void {
    self.execute(device, texture, input) catch |err| {
        self.result = .{ .failure = err };
    };
    self.state.store(.done, .release);
}

fn execute(
    self: *Self,
    device: *c.SDL_GPUDevice,
    texture: ?*c.SDL_GPUTexture,
    input: Input,
) !void {
    std.log.info("Task is running", .{});
    // 提取像素数据
    self.extracted = try Extractor.extract(self.allocator, device, texture, input.shape);
    // 选择模型：如果存在点击座标，则用 MagicTouch 否则用 BiRefNet
    const model: OrtRunner.Model = if (input.click != null) .magic_touch else .birefnet;
    const data_ptr = self.extracted.?.pixels_slice.ptr;
    const u_shape = input.shape.to(u32);
    const click_position: ?Point = if (input.click) |click| .{ .x = click.x, .y = click.y } else null;
    const runner_input: RunnerInput = .{
        .data_ptr = data_ptr,
        .shape = u_shape,
        .click_position = click_position,
    };
    // 运行模型推理
    try remover.init(self.allocator);
    var image = try remover.remove(model, runner_input);
    defer image.deinit();
    const out = try image.allocOutInMemory();
    self.result = .{ .success = .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data_ptr = out.data_ptr,
        ._out = out,
    } };
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
