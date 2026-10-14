const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const FrameSize = shared.Size2D(i32);
const icon_renderer = @import("icon_renderer.zig");
const Uploader = @import("../display/Uploader.zig");
const TextPipeline = @import("TextPipeline.zig");
const RectPipeline = @import("RectPipeline.zig");
const RectDrawer = @import("RectDrawer.zig");
const Rect = RectDrawer.Rect;
const Button = @import("Button.zig");
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Color = @import("Color.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

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
    color: Color = .rgba(0.15, 0.15, 0.15, 0.75),
    /// 标题栏高度（像素）。按钮为边长等于栏高的正方形，图标在其中居中。
    height: f32 = 44.0,
    /// 内部图标的配置。图标边长应小于栏高，二者之差即为按钮四周的等边距。
    icon: icon_renderer.Options = .{ .scale = 0.5 },
    /// close 按钮悬停时的背景色（默认半透明红）。
    hover_close: Color = .rgba(1.0, 0.0, 0.0, 0.5),
    /// minimize 按钮悬停时的背景色（默认半透明灰）。
    hover_minimize: Color = .rgba(0.5, 0.5, 0.5, 0.5),
    /// 调试开关：为背景与按钮叠加红色。
    debug: bool = false,
};

const transparent = Color.rgba(0.0, 0.0, 0.0, 0.0);

allocator: Allocator,
frame_size: FrameSize,
options: Options,
background: RectDrawer,
rect: Rect,
close: Button,
minimize: Button,

on_close: ?Event.Callback(void) = null,
on_minimize: ?Event.Callback(void) = null,
/// 任意按钮的悬停状态发生变化时触发，参数为「当前是否有按钮被悬停」。
on_button_hover: ?Event.Callback(bool) = null,

last_button_hover: bool = false,

pub fn init(
    allocator: Allocator,
    uploader: *Uploader,
    text_pipeline: *TextPipeline,
    rect_pipeline: *RectPipeline,
    frame_size: FrameSize,
    options: Options,
) Error!Self {
    const fw: f32 = @floatFromInt(frame_size.w);

    // 按钮为边长等于栏高的正方形，图标在其中居中，故四周等边距 = (栏高 - 图标边长) / 2。
    // 按钮按实际边长贴右缘排布：close 最右，minimize 在其左侧，因此二者不会重叠。
    const button_side = options.height;
    const icon_side: f32 = @floatFromInt(icon_renderer.frameSize(options.icon));
    const padding = @max(0.0, (button_side - icon_side) * 0.5);
    const rect = Rect{ .x = 0.0, .y = 0.0, .w = fw, .h = button_side };

    var background = try RectDrawer.init(uploader, rect_pipeline, frame_size, rect, options.color.value(), options.debug);
    errdefer background.deinit();

    const button_options = Button.Options{
        .padding = padding,
        .color = transparent,
        .icon = options.icon,
        .debug = options.debug,
    };
    var close = try Button.init(allocator, uploader, text_pipeline, rect_pipeline, frame_size, .close, .{ .x = fw - button_side, .y = 0.0 }, button_options);
    errdefer close.deinit();
    var minimize = try Button.init(allocator, uploader, text_pipeline, rect_pipeline, frame_size, .minimize, .{ .x = fw - button_side * 2.0, .y = 0.0 }, button_options);
    errdefer minimize.deinit();

    return Self{
        .allocator = allocator,
        .frame_size = frame_size,
        .options = options,
        .background = background,
        .rect = rect,
        .close = close,
        .minimize = minimize,
    };
}

pub fn deinit(self: *Self) void {
    self.close.deinit();
    self.minimize.deinit();
    self.background.deinit();
    self.* = undefined;
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
