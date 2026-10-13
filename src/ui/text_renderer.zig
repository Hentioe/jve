const std = @import("std");
const ass = @import("ass");
const strdup = @import("shared").strdup;
const Allocator = std.mem.Allocator;
const helper = @import("helper.zig");
const imageInkBounds = helper.imageInkBounds;
const fullBounds = helper.fullBounds;
const consts = @import("consts.zig");
const DEFAULT_FONT = consts.DEFAULT_FONT;
const DEFAULT_FONT_SIZE = consts.DEFAULT_FONT_SIZE;
const AssRendered = @import("AssRendered.zig");
const Error = @import("errors.zig").Error;

pub const Options = struct {
    font_name: []const u8 = DEFAULT_FONT, // 默认字体: Arial
    font_size: f64 = DEFAULT_FONT_SIZE, // 默认字体大小: 12
    bold: bool = false, // 默认不加粗
    color: u32 = 0xFFFFFF00, // ASS 颜色（0xRRGGBBAA，低字节 ASS alpha：0x00 不透明），默认不透明白
    spacing: f64 = 0, // 默认无间距
    trim: bool = true, // 是否按墨迹包围盒裁剪，去掉 libass 光栅化留下的 padding
};

pub fn render(allocator: Allocator, renderer: *const ass.Renderer, value: []const u8, options: Options) Error!AssRendered {
    const track = renderer.library.newTrack();
    errdefer ass.c.ass_free_track(track);
    const style_id = ass.Library.allocStyle(track);
    const style = &track.*.styles[@intCast(style_id)];
    style.*.Name = try strdup("Default");
    style.*.FontName = try strdup(options.font_name); // 关键，不能为 NULL
    style.*.FontSize = options.font_size;
    style.*.Bold = if (options.bold) 1 else 0;
    style.*.PrimaryColour = options.color;
    style.*.ScaleX = 1.0;
    style.*.ScaleY = 1.0;
    style.*.Alignment = ass.c.VALIGN_CENTER | ass.c.HALIGN_CENTER; // 画面正中
    style.*.MarginL = 0;
    style.*.MarginR = 0;
    style.*.MarginV = 0;
    style.*.Spacing = options.spacing;
    // 设置事件
    const event_id = ass.Library.allocEvent(track);
    const event = &track.*.events[@intCast(event_id)];
    event.*.Start = 0; // 起始时间固定为 0
    event.*.Duration = std.math.maxInt(c_longlong); // 时长固定为最大数字
    event.*.Style = style_id;
    event.*.Text = try strdup(value); // 事件文本（要渲染的文字）
    var detect_change: c_int = 0;
    const image = renderer.renderFrame(track, 0, &detect_change) orelse return Error.AssNotRendered;

    // 可选地裁剪到墨迹包围盒，去掉 libass 光栅化留下的 padding
    const bounds = if (options.trim)
        imageInkBounds(image) orelse fullBounds(image)
    else
        fullBounds(image);

    const w: usize = @intCast(bounds.w);
    const h: usize = @intCast(bounds.h);
    const pixels = try allocator.alloc(u8, w * h);
    errdefer allocator.free(pixels);
    // 逐行按 stride 拷贝覆盖率（最后一行不保证补齐）
    const stride: usize = @intCast(image.stride);
    const src_x: usize = @intCast(bounds.x);
    const src_y: usize = @intCast(bounds.y);
    var y: usize = 0;
    while (y < h) : (y += 1) {
        const row = image.bitmap + (src_y + y) * stride;
        @memcpy(pixels[y * w ..][0..w], row[src_x..][0..w]);
    }

    return AssRendered{
        .allocator = allocator,
        .track = track,
        .width = @intCast(w),
        .height = @intCast(h),
        .pixels = pixels,
        .color = image.color,
        .detect_change = detect_change,
    };
}
