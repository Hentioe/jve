const std = @import("std");
const ort = @import("ort");
const Allocator = std.mem.Allocator;
const Image = @import("../vips.zig").Image;
const Api = ort.Api;
const Session = ort.Session;
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
    // 打印输入的基本信息
    std.log.info("Image size: {d}x{d}, bands: {d}", .{ input.width, input.height, input.bands });

    // 前处理：强制 3 通道、缩放、归一化、NCHW 布局
    var preprocessed = try input.preprocess(allocator, .{
        .forced_bands = 3,
        .new_size = .{ .w = SIZE, .h = SIZE },
        .normalized = true,
        .new_layout = .NCHW,
    });
    defer preprocessed.deinit();

    // 确保图片符合 BiRefNet 模型的输入要求：必须是 3 通道的图像，且宽高为 1024x1024
    std.debug.assert(preprocessed.bands == 3);
    std.debug.assert(preprocessed.width == SIZE);
    std.debug.assert(preprocessed.height == SIZE);

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
    const output_sensor = try self.session.run(input_tensor);
    defer self.api.releaseValue(output_sensor);
    std.log.info("Background removal completed", .{});

    // 后处理：解析输出、添加透明通道、缩放回原始尺寸
    const output_ptr = try self.api.getTensorMutableData(output_sensor);
    var image = try Output.parse(
        allocator,
        output_ptr,
        .{ .w = SIZE, .h = SIZE },
        1,
        .FLOAT,
        .NCHW,
        true,
        true,
    );

    try image.resize(@intCast(input.width), @intCast(input.height));
    try image.toRgb();
    try image.addAlpha(255.0);

    return image;
}
