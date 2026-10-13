const std = @import("std");
const ass = @import("ass");
const strdup = @import("shared").strdup;
const Allocator = std.mem.Allocator;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const consts = @import("consts.zig");
const AssRendered = @import("AssRendered.zig");
const IconRenderer = @import("IconRenderer.zig");

pub const Options = struct {
    /// ASS 颜色（0xRRGGBBAA，低字节为 ASS alpha：0x00 不透明、0xFF 全透明）。
    /// 直接写入 `ASS_Style.PrimaryColour`；默认不透明白。
    color: u32 = 0xFFFFFF00,
    scale: f32 = 1.0, // 缩放比例
};

pub fn render(allocator: Allocator, value: []const u8, options: Options) Error!AssRendered {
    const renderer = IconRenderer.get();
    // 输出边长：scale = 1 时为 BASE_SIZE，随 scale 线性缩放。
    const frame: u32 = @intFromFloat(@round(@as(f32, @floatFromInt(IconRenderer.BASE_SIZE)) * options.scale));
    renderer.setFrameSize(@intCast(frame), @intCast(frame));
    const track = renderer.library.newTrack();
    track.PlayResX = IconRenderer.PLAY_RES;
    track.PlayResY = IconRenderer.PLAY_RES;
    errdefer ass.c.ass_free_track(track);
    const style_id = ass.Library.allocStyle(track);
    const style = &track.*.styles[@intCast(style_id)];
    style.*.Name = try strdup("Default");
    style.*.FontName = try strdup(consts.DEFAULT_FONT); // 关键，不能为 NULL
    style.*.PrimaryColour = options.color;
    style.*.OutlineColour = options.color;
    style.*.ScaleX = 1.0;
    style.*.ScaleY = 1.0;
    style.*.Alignment = ass.c.VALIGN_TOP | ass.c.HALIGN_LEFT; // 左上角锚点
    style.*.MarginL = 0;
    style.*.MarginR = 0;
    style.*.MarginV = 0;
    // 设置事件
    const event_id = ass.Library.allocEvent(track);
    const event = &track.*.events[@intCast(event_id)];
    event.*.Start = 0; // 起始时间固定为 0
    event.*.Duration = std.math.maxInt(c_longlong); // 时长固定为最大数字
    event.*.Style = style_id;
    event.*.Text = try strdup(value); // 事件文本（要渲染的文字）
    var detect_change: c_int = 0;
    const first = renderer.renderFrame(track, 0, &detect_change) orelse return Error.AssNotRendered;

    // 按 dst_x/dst_y 把所有图层合成到整幅 frame×frame 画布。图标按画布尺寸
    // 设计，因此直接返回整幅画布——不需要墨迹裁剪：超出画布的 libass padding
    // 会被裁掉，画布内没有墨迹的地方即单元格的透明留白。
    const pixels = try helper.compose(allocator, first, frame, frame);

    return AssRendered{
        .allocator = allocator,
        .track = track,
        .width = frame,
        .height = frame,
        .pixels = pixels,
        // 颜色由外部 options 决定（图标只描述几何），libass 会原样透传到
        // image.color；这里直接用 libass 产出的 ASS 颜色交给管线解码。
        .color = first.color,
        .detect_change = detect_change,
    };
}
