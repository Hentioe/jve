const std = @import("std");
const ort = @import("ort");
const Allocator = std.mem.Allocator;
const Image = @import("../vips.zig").Image;
const Api = ort.Api;
const Session = ort.Session;
const Timer = @import("Timer.zig");
const Input = @import("processors/Input.zig");
const Output = @import("processors/Output.zig");
const Position = @import("Position.zig");
const Self = @This();

const SIZE = 512;
const ROI_RADIUS: f32 = 5.0;

api: *const Api,
session: Session,

pub fn init(api: *const Api) !Self {
    const session = try api.createSession("models/magic_touch.onnx", .{ .disable_gpu = true });

    return .{ .api = api, .session = session };
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.* = undefined;
}

pub fn run(self: *const Self, allocator: Allocator, input: Input) !Image {
    // 打印输入的基本信息
    std.log.info("Image shape: {f}", .{input.shape});
    // 前处理：强制 3 通道、缩放、归一化
    var preprocessed = try input.preprocess(allocator, .{
        .forced_channels = 3,
        .new_size = .{ .w = SIZE, .h = SIZE },
        .normalized = true,
    });
    defer preprocessed.deinit();

    // 确保图片符合 MagicTouch 模型的输入要求：必须是 3 通道的图像，且宽高为 512x512
    std.debug.assert(preprocessed.shape.c == 3);
    std.debug.assert(preprocessed.shape.w == SIZE);
    std.debug.assert(preprocessed.shape.h == SIZE);

    // 按官方方式生成 ROI prior map：在原始分辨率上以点击点为中心画圆，
    // 再缩放到模型输入尺寸（与图像缩放一致）。
    const prior = try buildPriorMap(allocator, input);
    defer allocator.free(prior);

    // 组装 4 通道输入：RGB + ROI prior map
    const loaded_data = preprocessed.Data(f32);
    var input_data = try allocator.alloc(f32, SIZE * SIZE * 4);
    defer allocator.free(input_data);
    for (0..SIZE * SIZE) |i| {
        input_data[i * 4 + 0] = loaded_data[i * 3 + 0];
        input_data[i * 4 + 1] = loaded_data[i * 3 + 1];
        input_data[i * 4 + 2] = loaded_data[i * 3 + 2];
        input_data[i * 4 + 3] = prior[i];
    }

    // 构造输入张量
    const input_shape = [_]i64{ 1, SIZE, SIZE, 4 };
    const input_shape_ptr: [*]const i64 = &input_shape;
    const input_data_bytes = @sizeOf(f32) * input_data.len;
    const input_tensor = try self.session.createTensorWithData(
        input_shape_ptr,
        input_shape.len,
        input_data.ptr,
        input_data_bytes,
    );
    defer self.api.releaseValue(input_tensor);

    // 执行推理并获取输出指针
    std.log.info("Background removal in progress...", .{});
    var timer: Timer = try .start();
    const output_sensor = try self.session.run(input_tensor);
    defer self.api.releaseValue(output_sensor);
    std.log.info("Background removal took {d}ms", .{try timer.finish(.ms)});
    std.log.info("Background removal completed", .{});

    // 后处理：解析输出、添加透明通道、缩放回原始尺寸。
    // MagicTouch 的 ONNX 末端已带 Sigmoid，输出本身就是 [0,1] 概率图，故 apply_sigmoid 传 false。
    const output_ptr = try self.api.getTensorMutableData(output_sensor);
    var image = try Output.parse(
        allocator,
        output_ptr,
        .{ .w = SIZE, .h = SIZE, .c = 1 },
        .FLOAT,
        .NCHW,
        true,
        false,
    );
    const original_size = input.shape.toISize(i32);
    try image.resize(original_size.w, original_size.h);
    try image.toRgb();
    try image.addAlpha(255.0);

    return image;
}

// 生成 ROI prior map：在原始分辨率上以点击点为中心画一个半径 ROI_RADIUS 的圆，
// 再缩放到模型输入尺寸（与图像缩放保持一致）。未提供点击坐标时退化为图像中心。
fn buildPriorMap(allocator: Allocator, input: Input) ![]f32 {
    const f_size = input.shape.toISize(f32);
    const point = input.click_position orelse Position{
        .x = f_size.w / 2.0,
        .y = f_size.h / 2.0,
    };

    const u_shape = input.shape.to(u32);
    const w = u_shape.w;
    const h = u_shape.h;
    const raw = try allocator.alloc(f32, w * h);
    defer allocator.free(raw);
    @memset(raw, 0.0);

    const radius_sq = ROI_RADIUS * ROI_RADIUS;
    const x_start: u32 = @intFromFloat(@max(0.0, point.x - ROI_RADIUS - 1.0));
    const y_start: u32 = @intFromFloat(@max(0.0, point.y - ROI_RADIUS - 1.0));
    const x_end: u32 = @min(w, @as(u32, @intFromFloat(@max(0.0, point.x + ROI_RADIUS + 1.0))) + 1);
    const y_end: u32 = @min(h, @as(u32, @intFromFloat(@max(0.0, point.y + ROI_RADIUS + 1.0))) + 1);
    var y = y_start;
    while (y < y_end) : (y += 1) {
        var x = x_start;
        while (x < x_end) : (x += 1) {
            const dx = @as(f32, @floatFromInt(x)) + 0.5 - point.x;
            const dy = @as(f32, @floatFromInt(y)) + 0.5 - point.y;
            if (dx * dx + dy * dy <= radius_sq) {
                raw[y * w + x] = 1.0;
            }
        }
    }

    const prior_size = input.shape.toISize(i32);
    var image = try Image.init(raw.ptr, .{ .w = prior_size.w, .h = prior_size.h, .c = 1 }, .FLOAT);
    defer image.deinit();
    try image.resize(SIZE, SIZE);
    var out = try image.allocOutInMemory();
    defer out.deinit();
    const resized = @as([*]const f32, @ptrCast(@alignCast(out.data_ptr)))[0 .. SIZE * SIZE];

    const prior = try allocator.alloc(f32, SIZE * SIZE);
    for (resized, 0..) |v, i| prior[i] = std.math.clamp(v, 0.0, 1.0);
    return prior;
}
