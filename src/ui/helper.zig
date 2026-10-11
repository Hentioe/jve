const std = @import("std");
const ass = @import("ass");

/// ASS_Image 位图中「墨迹」的紧致矩形（图像局部坐标，单位像素）。
pub const Bounds = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

/// 整幅位图的边界。
pub fn fullBounds(img: *const ass.c.ASS_Image) Bounds {
    return .{ .x = 0, .y = 0, .w = img.w, .h = img.h };
}

/// 计算 ASS_Image 位图的「墨迹包围盒」——覆盖率非零的最小矩形区域。
///
/// 为什么需要它：libass 的 `ass_outline_to_bitmap()` 会给每个 glyph 位图加上
/// 固定 padding（左侧约 1px、右侧由 `+127` 多出约 2px），再把宽高按光栅化
/// tile 尺寸（`tile_order=4`，即 16px；large tiles 为 32px）向上对齐；单张
/// 位图合成时又被原样拷贝。因此 `ASS_Image` 的右侧最多可多出 tile-1 像素的
/// 透明列（文字、矢量图形、图标都一样）。裁剪到墨迹包围盒可做到像素级精确对齐。
///
/// 位图为每像素 1 字节，行间按 stride 对齐，且最后一行可能未补齐，因此必须
/// 逐行用 stride 定位。整幅全透明（无墨迹）时返回 null。
pub fn imageInkBounds(img: *const ass.c.ASS_Image) ?Bounds {
    if (img.w <= 0 or img.h <= 0) return null;
    const stride: usize = @intCast(img.stride);
    var min_x: i32 = img.w;
    var min_y: i32 = img.h;
    var max_x: i32 = -1;
    var max_y: i32 = -1;
    var y: i32 = 0;
    while (y < img.h) : (y += 1) {
        const row = img.bitmap + @as(usize, @intCast(y)) * stride;
        var x: i32 = 0;
        while (x < img.w) : (x += 1) {
            if (row[@intCast(x)] == 0) continue;
            if (x < min_x) min_x = x;
            if (x > max_x) max_x = x;
            if (y < min_y) min_y = y;
            if (y > max_y) max_y = y;
        }
    }
    if (max_x < 0) return null;
    return .{ .x = min_x, .y = min_y, .w = max_x - min_x + 1, .h = max_y - min_y + 1 };
}

/// 把 libass 返回的整条图层链按 `dst_x` / `dst_y` 合成到一张
/// `width × height` 的画布上（覆盖率取各层最大值）。
///
/// libass 对每个 event 只光栅化其墨迹的紧致区域，实际位置放在 `dst_x` /
/// `dst_y`。若只取单张位图而丢掉偏移，`\pos` / 对齐就会被抹掉（图标贴角）。
/// 合成为整幅画布后，位置信息得以保留。
pub fn compose(allocator: std.mem.Allocator, first: *ass.c.ASS_Image, width: u32, height: u32) std.mem.Allocator.Error![]u8 {
    const pixels = try allocator.alloc(u8, @as(usize, width) * height);
    @memset(pixels, 0);
    var img: *ass.c.ASS_Image = first;
    while (true) {
        const iw: i64 = img.w;
        const ih: i64 = img.h;
        const stride: usize = @intCast(img.stride);
        const dx: i64 = img.dst_x;
        const dy: i64 = img.dst_y;
        var y: usize = 0;
        while (y < @as(usize, @intCast(ih))) : (y += 1) {
            const ty: i64 = dy + @as(i64, @intCast(y));
            if (ty < 0 or ty >= @as(i64, height)) continue;
            const row = img.bitmap + y * stride;
            var x: usize = 0;
            while (x < @as(usize, @intCast(iw))) : (x += 1) {
                const tx: i64 = dx + @as(i64, @intCast(x));
                if (tx < 0 or tx >= @as(i64, width)) continue;
                const v = row[x];
                const dst = &pixels[@as(usize, @intCast(ty)) * @as(usize, width) + @as(usize, @intCast(tx))];
                if (v > dst.*) dst.* = v;
            }
        }
        if (img.next == null) break;
        img = img.next;
    }
    return pixels;
}

/// 计算覆盖率画布中非零像素的紧致包围盒；整幅全透明时返回 null。
pub fn inkBounds(pixels: []const u8, width: u32, height: u32) ?Bounds {
    var min_x: i32 = @intCast(width);
    var min_y: i32 = @intCast(height);
    var max_x: i32 = -1;
    var max_y: i32 = -1;
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            if (pixels[@as(usize, y) * @as(usize, width) + @as(usize, x)] == 0) continue;
            if (x < min_x) min_x = @intCast(x);
            if (x > max_x) max_x = @intCast(x);
            if (y < min_y) min_y = @intCast(y);
            if (y > max_y) max_y = @intCast(y);
        }
    }
    if (max_x < 0) return null;
    return .{ .x = min_x, .y = min_y, .w = max_x - min_x + 1, .h = max_y - min_y + 1 };
}
