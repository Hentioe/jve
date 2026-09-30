const std = @import("std");
const enums = @import("../enums.zig");
const Allocator = std.mem.Allocator;
const Image = @import("../../vips.zig").Image;
const Size = enums.Size;
const PixelLayout = enums.PixelLayout;
const Format = Image.Format;
const Self = @This();

const Postprocessed = struct {};

pub fn parse(allocator: Allocator, output_ptr: *anyopaque, size: Size, bands: i32, format: Format, layout: PixelLayout, normalized: bool) !Image {
    var image: Image = undefined;
    if (layout == .NCHW) {
        std.debug.assert(normalized and format == .FLOAT); // 目前仅支持转换归一化的浮点格式数据
        // 转换为 NCHW 布局
        const u_width: usize = @intCast(size.w);
        const u_height: usize = @intCast(size.h);
        const u_bands: usize = @intCast(bands);
        const src = @as([*]f32, @ptrCast(@alignCast(output_ptr)))[0 .. u_width * u_height * u_bands];
        const data = try buildNHWC(allocator, src, @intCast(size.w), @intCast(size.h), @intCast(bands));
        defer allocator.free(data);
        image = try Image.init(
            data.ptr,
            size.w,
            size.h,
            bands,
            .UCHAR,
        );
    } else {
        image = try Image.init(
            output_ptr,
            size.w,
            size.h,
            bands,
            format,
        );
    }

    return image;
}

// todo: 添加错误处理集
pub fn buildNHWC(allocator: Allocator, src: []const f32, width: u32, height: u32, bands: u32) ![]u8 {
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
