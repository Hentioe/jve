const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const FrameSize = shared.Size2D(i32);
const icon_renderer = @import("icon_renderer.zig");
const text_renderer = @import("text_renderer.zig");
const consts = @import("consts.zig");
const AssLibrary = @import("AssLibrary.zig");
const Text = @import("Text.zig");
const pipeline_registry = @import("../pipelines/registry.zig");
const RectDrawer = @import("RectDrawer.zig");
const Rect = RectDrawer.Rect;
const Button = @import("Button.zig");
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Color = @import("Color.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 标题文字单独使用的 ass 渲染画布：固定尺寸、与窗口无关。
///
/// 画布高取 libass 参考分辨率 `PLAY_RES_Y`，使缩放系数 `frame_h / PLAY_RES_Y = 1`：
/// 于是「合适的文字高度」就是基准——`title.font_size` 直接写该像素高度即可。
/// 宽度取足够大以免 libass 自动换行（缩略截断由 `Text` 按 `max_width` 负责）。
const TITLE_FRAME = FrameSize{ .w = 4096, .h = text_renderer.PLAY_RES_Y };

/// 窗口标题栏：始终位于窗口顶部、占满整宽的背景条，右侧自带 `close` 与
/// `minimize` 两个 `Button`。
///
/// 背景色可控；对外只暴露 `on_close` / `on_minimize`。两个按钮的点击被内部
/// 封装并转发到这两个回调，悬停效果也由内部实现（close 悬停半透明红，
/// minimize 悬停半透明灰）。
///
/// 注意：两个按钮的回调需要引用 TitleBar 自身地址，因此必须在 TitleBar 落到
/// 最终地址后调用一次 `bindEvents`（与 `events.Context.bindEvents` 同理）。
pub const Options = struct {
    /// 背景色（RGBA，0..1），默认深色半透明，确保在深色背景上可见。
    color: Color = .rgba01(0.15, 0.15, 0.15, 0.75),
    /// 标题栏高度（像素）。按钮为边长等于栏高的正方形，图标在其中居中。
    height: f32 = 44.0,
    /// 内部图标的配置。图标边长应小于栏高，二者之差即为按钮四周的等边距。
    icon: icon_renderer.Options = .{ .scale = 0.5 },
    /// 标题文字的样式（字体/字号/颜色等）。`font_size` 即文字像素高度（基准）；
    /// `max_width` 由组件按栏宽自动计算。
    title: text_renderer.Options = .{ .font_size = 30, .color = 0xFFFFFF20 },
    /// 标题文字与两侧按钮之间的留白（像素）。
    title_margin: f32 = 8.0,
    /// close 按钮悬停时的背景色（默认半透明红）。
    hover_close: Color = .rgba01(1.0, 0.0, 0.0, 0.5),
    /// minimize 按钮悬停时的背景色（默认半透明灰）。
    hover_minimize: Color = .rgba01(0.5, 0.5, 0.5, 0.5),
    /// 调试开关：为背景与按钮叠加红色。
    debug: bool = false,
};

const transparent = Color.rgba01(0.0, 0.0, 0.0, 0.0);

allocator: Allocator,
frame_size: FrameSize,
options: Options,
renderer: ass.Renderer,
background: RectDrawer,
rect: Rect,
close: Button,
minimize: Button,
title: ?Text = null,

on_close: ?Event.Callback(void) = null,
on_minimize: ?Event.Callback(void) = null,
/// 任意按钮的悬停状态发生变化时触发，参数为「当前是否有按钮被悬停」。
on_button_hover: ?Event.Callback(bool) = null,

last_button_hover: bool = false,

pub fn init(
    allocator: Allocator,
    frame_size: FrameSize,
    options: Options,
) Error!Self {
    const fw: f32 = @floatFromInt(frame_size.w);

    // 自持一个固定尺寸的 ass 渲染器专门渲染标题文字（不随窗口变化，也不与图标共用）。
    var renderer = try ass.Renderer.init(try AssLibrary.get());
    errdefer renderer.deinit("title bar");
    renderer.setFonts(null, consts.DEFAULT_FONT, ass.c.ASS_FONTPROVIDER_AUTODETECT, null, 1);
    renderer.setFrameSize(TITLE_FRAME.w, TITLE_FRAME.h);

    // 按钮为边长等于栏高的正方形，图标在其中居中，故四周等边距 = (栏高 - 图标边长) / 2。
    // 按钮按实际边长贴右缘排布：close 最右，minimize 在其左侧，因此二者不会重叠。
    const button_side = options.height;
    const icon_side: f32 = @floatFromInt(icon_renderer.frameSize(options.icon));
    const padding = @max(0.0, (button_side - icon_side) * 0.5);
    const rect = Rect{ .x = 0.0, .y = 0.0, .w = fw, .h = button_side };

    const rect_pipeline = try pipeline_registry.rect();
    var background = try RectDrawer.init(rect_pipeline, frame_size, rect, options.color.value(), options.debug);
    errdefer background.deinit();

    const button_options = Button.Options{
        .padding = padding,
        .color = transparent,
        .icon = options.icon,
        .debug = options.debug,
    };
    var close = try Button.init(allocator, frame_size, .close, .{ .x = fw - button_side, .y = 0.0 }, button_options);
    errdefer close.deinit();
    var minimize = try Button.init(allocator, frame_size, .minimize, .{ .x = fw - button_side * 2.0, .y = 0.0 }, button_options);
    errdefer minimize.deinit();

    return Self{
        .allocator = allocator,
        .frame_size = frame_size,
        .options = options,
        .renderer = renderer,
        .background = background,
        .rect = rect,
        .close = close,
        .minimize = minimize,
    };
}

pub fn deinit(self: *Self) void {
    self.clearTitle();
    self.close.deinit();
    self.minimize.deinit();
    self.background.deinit();
    self.renderer.deinit("title bar");
    self.* = undefined;
}

/// 释放当前标题文字。
fn clearTitle(self: *Self) void {
    if (self.title) |*t| t.deinit();
    self.title = null;
}

/// 设置（或替换）居中标题文字。过宽时由 `Text` 截断为「头…尾」。
pub fn setText(self: *Self, value: []const u8) Error!void {
    self.clearTitle();

    const fw: f32 = @floatFromInt(self.frame_size.w);
    // 文字按整条栏宽对称居中，左右各占 tw/2；右侧两列按钮共 2*height，
    // 为使右缘不越过 minimize 左缘，需在两侧各预留 2*height（共 4*height）。
    const reserved = (self.options.height * 2.0 + self.options.title_margin) * 2.0;
    const available = @max(0.0, fw - reserved);
    var title_options = self.options.title;
    title_options.max_width = available;

    var title = try Text.init(self.allocator, &self.renderer, value, title_options);
    errdefer title.deinit();

    const size = title.raster.size();
    const tw: f32 = @floatFromInt(size.w);
    const th: f32 = @floatFromInt(size.h);
    _ = title.position(.{ .x = (fw - tw) * 0.5, .y = (self.options.height - th) * 0.5 });
    title.debug(self.options.debug);

    _ = try title.toWidget(self.frame_size);

    self.title = title;
}

/// 绑定两个内部按钮的悬停/点击回调。必须在 TitleBar 位于最终地址后调用一次。
pub fn bindEvents(self: *Self) void {
    self.close.on_hover = Event.Callback(bool).bind(self, Self.closeHover);
    self.close.on_click = Event.Callback(void).bind(self, Self.closeClick);
    self.minimize.on_hover = Event.Callback(bool).bind(self, Self.minimizeHover);
    self.minimize.on_click = Event.Callback(void).bind(self, Self.minimizeClick);
}

fn closeHover(self: *Self, hovered: bool) void {
    self.close.setColor(if (hovered) self.options.hover_close else transparent);
}

fn closeClick(self: *Self, _: void) void {
    if (self.on_close) |cb| cb.call({});
}

fn minimizeHover(self: *Self, hovered: bool) void {
    self.minimize.setColor(if (hovered) self.options.hover_minimize else transparent);
}

fn minimizeClick(self: *Self, _: void) void {
    if (self.on_minimize) |cb| cb.call({});
}

/// 设置背景色。
pub fn setColor(self: *Self, color: Color) void {
    self.options.color = color;
    self.background.update(self.frame_size, self.rect, color.value(), self.options.debug);
}

pub fn toWidget(self: *Self) Widget {
    return .{
        .ptr = @ptrCast(self),
        .vtable = Widget.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.background.draw(cmd, pass);
    if (self.title) |*t| t.draw(cmd, pass);
    self.close.draw(cmd, pass);
    self.minimize.draw(cmd, pass);
}

pub fn event(self: *Self, e: *const Event) void {
    self.close.event(e);
    self.minimize.event(e);

    // 任意按钮的悬停状态变化都汇聚成一个「是否有按钮被悬停」的信号。
    const any_hover = self.close.last_hover or self.minimize.last_hover;
    if (any_hover != self.last_button_hover) {
        self.last_button_hover = any_hover;
        if (self.on_button_hover) |cb| cb.call(any_hover);
    }
}
