const std = @import("std");
const ort = @import("ort");
const heap = @import("../heap.zig");
const Allocator = std.mem.Allocator;
const Image = @import("../vips.zig").Image;
const Api = ort.Api;
const Session = ort.Session;
const Timer = @import("Timer.zig");
const Input = @import("processors/Input.zig");
const Output = @import("processors/Output.zig");
const Self = @This();

const Variant = enum { lite, normal };
const SIZE = 1024;

api: *const Api,
session: Session,
variant: Variant,

pub fn init(api: *const Api, variant: Variant) !Self {
    const session = try switch (variant) {
        .lite => api.createSession("models/BiRefNet_lite.onnx", .{ .disable_gpu = true }),
        .normal => api.createSession("models/BiRefNet.onnx", .{ .disable_gpu = true }),
    };

    return .{ .api = api, .session = session, .variant = variant };
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.* = undefined;
}

pub fn run(self: *const Self, allocator: Allocator, input: Input) !Image {
    // 所有张量释放后归还空闲堆给操作系统
    defer heap.trimHeap();
    // 打印输入的基本信息
    std.log.info("Image shape: {f}", .{input.shape});

    // 前处理：强制 3 通道、缩放、归一化、NCHW 布局
    var preprocessed = try input.preprocess(allocator, .{
        .forced_channels = 3,
        .new_size = .{ .w = SIZE, .h = SIZE },
        .normalized = true,
        .new_layout = .NCHW,
    });
    defer preprocessed.deinit();

    // 确保图片符合 BiRefNet 模型的输入要求：必须是 3 通道的图像，且宽高为 1024x1024
    std.debug.assert(preprocessed.shape.c == 3);
    std.debug.assert(preprocessed.shape.w == SIZE);
    std.debug.assert(preprocessed.shape.h == SIZE);

    // 构造输入张量
    const input_shape = [_]i64{ 1, 3, SIZE, SIZE };
    const input_shape_ptr: [*]const i64 = &input_shape;
    const input_tensor = try self.session.createTensorWithData(
        input_shape_ptr,
        input_shape.len,
        preprocessed.data_ptr,
        preprocessed.data_size,
    );
    defer self.api.releaseValue(input_tensor);

    // 执行推理并获取输出指针
    std.log.info("Background removal in progress...", .{});
    var timer: Timer = try .start();
    const output_sensor = try self.session.run(input_tensor);
    defer self.api.releaseValue(output_sensor);
    std.log.info("Background removal took {d}s", .{try timer.finish(.s)});
    std.log.info("Background removal completed", .{});

    // 后处理：解析输出、添加透明通道、缩放回原始尺寸
    const output_ptr = try self.api.getTensorMutableData(output_sensor);
    var image = try Output.parse(
        allocator,
        output_ptr,
        .{ .w = SIZE, .h = SIZE, .c = 1 },
        .FLOAT,
        .NCHW,
        true,
        true,
    );

    const original_size = input.shape.toISize(i32);
    try image.resize(original_size.w, original_size.h);
    try image.toRgb();
    try image.addAlpha(255.0);

    return image;
}
