const std = @import("std");
const ort = @import("ort");
const resizer = @import("../root.zig").resizer;
const Allocator = std.mem.Allocator;
const Api = ort.Api;
const Session = ort.Session;
const Self = @This();

const Input = struct {
    data_ptr: *const anyopaque,
    bands: u32,
    width: u32,
    height: u32,
};
const Size = struct { w: i32, h: i32 };
const Variant = enum { lite, normal };

const PIXEL_COUNT = 1024 * 1024;

api: *const Api,
session: Session,
variant: Variant,

pub fn init(api: *const Api, variant: Variant) !Self {
    const session = try switch (variant) {
        .lite => api.createSession("models/BiRefNet_lite.onnx", .{}),
        .normal => api.createSession("models/BiRefNet.onnx", .{}),
    };

    return .{
        .api = api,
        .session = session,
        .variant = variant,
    };
}

pub fn deinit(self: *Self) void {
    self.session.deinit();
    self.* = undefined;
}

pub fn run(self: *const Self, allocator: Allocator, input: Input) !resizer.Result {
    // 前处理：缩放、归一化、NCHW 布局
    var resized_input = try resizer.resize( // 缩放、归一化、强制通道数为 3
        input.data_ptr,
        @intCast(input.width),
        @intCast(input.height),
        @intCast(input.bands),
        1024,
        1024,
        .{ .output_normalize = true, .force_input_bands = 3 },
    );
    defer resized_input.deinit();

    // 打印输入的基本信息
    std.log.info("Image size: {d}x{d}, bands: {d}", .{ input.width, input.height, input.bands });

    // 确保图片符合 BiRefNet 模型的输入要求：必须是 3 通道的图像，且宽高为 1024x1024
    std.debug.assert(resized_input.bands == 3);
    std.debug.assert(resized_input.width == 1024);
    std.debug.assert(resized_input.height == 1024);

    // 生成 NCHW 布局数据
    const src_len = 1024 * 1024 * resized_input.bands;
    const src_data = @as([*]const f32, @ptrCast(@alignCast(resized_input.data_ptr)))[0..src_len];
    const nchw_data = try preprocess(allocator, src_data, 1024, 1024, 3);
    defer allocator.free(nchw_data);

    // 构造输入张量
    const input_shape = [_]i64{ 1, 3, 1024, 1024 };
    const input_data_bytes = @sizeOf(f32) * (resized_input.width * resized_input.height * 3);
    const input_shape_ptr: [*]const i64 = &input_shape;
    const input_tensor = try self.session.createTensorWithData(
        input_shape_ptr,
        input_shape.len,
        nchw_data.ptr,
        input_data_bytes,
    );
    defer self.api.releaseValue(input_tensor);

    // 执行推理并获取输出指针
    std.log.info("Background removal in progress...", .{});
    const output_sensor = try self.session.run(input_tensor);
    defer self.api.releaseValue(output_sensor);
    std.log.info("Background removal completed", .{});

    // 后处理：解析输出、缩放回原始尺寸
    const output_ptr = try self.api.getTensorMutableData(output_sensor);
    const output_f32_ptr: [*]f32 = @ptrCast(@alignCast(output_ptr));
    const output_data = output_f32_ptr[0 .. PIXEL_COUNT * 3];
    const nhwc_data = try postprocess(allocator, output_data, 1024, 1024, 3);
    defer allocator.free(nhwc_data);

    return try resizer.resize( // 缩放回原始尺寸
        nhwc_data.ptr,
        1024,
        1024,
        3,
        @intCast(input.width),
        @intCast(input.height),
        .{ .force_output_bands = 4 },
    );
}

// 前处理：NHWC -> NCHW
// todo: 添加错误处理集
pub fn preprocess(allocator: Allocator, src: []const f32, width: u32, height: u32, bands: u32) ![]f32 {
    const plane_size = width * height;
    const dst = try allocator.alloc(f32, plane_size * bands);
    for (0..height) |h| {
        for (0..width) |w| {
            const hwc_idx = (h * width + w) * bands;
            const hw_idx = h * width + w;
            for (0..bands) |c| {
                const idx = c * plane_size + hw_idx;
                dst[idx] = src[hwc_idx + c];
            }
        }
    }
    return dst;
}

// 后处理：NCHW -> NHWC
// todo: 添加错误处理集
pub fn postprocess(allocator: Allocator, src: []const f32, width: u32, height: u32, bands: u32) ![]u8 {
    const plane_size = width * height;
    const dst = try allocator.alloc(u8, plane_size * bands);

    for (0..height) |h| {
        const row_off = h * width;
        for (0..width) |w| {
            const hw_idx = row_off + w;
            const hwc_idx = hw_idx * bands;
            for (0..bands) |c| {
                const idx = c * plane_size + hw_idx;
                // Sigmoid 转成 [0.0, 1.0] 连续概率
                const prob = 1.0 / (1.0 + std.math.exp(-src[idx]));
                // 乘以 255.0 并转成 u8（保留连续灰度/Alpha）
                const val = std.math.clamp(prob * 255.0, 0.0, 255.0);
                dst[hwc_idx + c] = @intFromFloat(val);
            }
        }
    }
    return dst;
}
