const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const WindowSize = shared.Size2D(i32);
const Text = @import("Text.zig");
const TextPipeline = @import("TextPipeline.zig");
const BannerPipeline = @import("BannerPipeline.zig");
const BannerDrawer = @import("BannerDrawer.zig");
const text_renderer = @import("text_renderer.zig");
const Uploader = @import("../display/Uploader.zig");
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Color = @import("Color.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 视口底部全宽横幅：背景由 `BannerPipeline`/`BannerDrawer` 绘制，文字是即时的
/// `Text` 组件。横幅高度随文字高度自适应，文字在容器内居中，位置无需外部提供。
///
/// 显示与否由外部决定：不调用 `draw` 即自然消失，因此通常作为独立字段传递。
pub const Options = struct {
    /// 背景色（RGBA，0..1）。
    color: Color = .rgba(1.0, 0.0, 0.0, 1.0),
    /// 文字距横幅上下边缘的留白（像素）。
    padding_y: f32 = 8.0,
    /// 横幅底边距视口底部的距离（像素）。
    margin_bottom: f32 = 24.0,
    /// 调试开关：把背景强制成红色。
    debug: bool = false,
    /// 内部文字组件的样式。
    text: text_renderer.Options = .{
        .font_name = "Noto Sans",
        .font_size = 12,
        .spacing = 0.75,
    },
};

allocator: Allocator,
renderer: *const ass.Renderer,
window_size: WindowSize,
uploader: *Uploader,
text_pipeline: *TextPipeline,
options: Options,
background: BannerDrawer,
text: ?Text = null,
rect_top: f32 = 0,
rect_height: f32 = 0,

on_hover: ?Event.Callback(bool) = null,
on_click: ?Event.Callback(void) = null,

last_hover: bool = false,

pub fn init(
    allocator: Allocator,
    renderer: *const ass.Renderer,
    window_size: WindowSize,
    uploader: *Uploader,
    text_pipeline: *TextPipeline,
    banner_pipeline: *BannerPipeline,
    options: Options,
) Error!Self {
    // 尚无文字时先给一个高度为 0 的横幅（不可见），`setText` 会按文字尺寸重建
    const fh: f32 = @floatFromInt(window_size.h);
    const top = fh - options.margin_bottom;
    const background = try BannerDrawer.init(uploader, banner_pipeline, window_size, top, 0, options.color.value(), options.debug);
    return Self{
        .allocator = allocator,
        .renderer = renderer,
        .window_size = window_size,
        .uploader = uploader,
        .text_pipeline = text_pipeline,
        .options = options,
        .background = background,
        .rect_top = top,
    };
}

pub fn deinit(self: *Self) void {
    if (self.text) |*t| t.deinit();
    self.background.deinit();
    self.* = undefined;
}

/// 设置（或替换）横幅文字。会即时重建文字组件，并按其尺寸自适应容器高度。
pub fn setText(self: *Self, message: []const u8) Error!void {
    if (self.text) |*t| t.deinit();
    self.text = null;

    self.text = try Text.init(self.allocator, self.renderer, message, self.options.text);
    errdefer {
        if (self.text) |*t| t.deinit();
        self.text = null;
    }
    const t = &self.text.?;

    // 容器尺寸：全宽，高 = 文字高 + 上下留白，靠下
    const text_size = t.raster.size();
    const text_w: f32 = @floatFromInt(text_size.w);
    const text_h: f32 = @floatFromInt(text_size.h);
    const fw: f32 = @floatFromInt(self.window_size.w);
    const fh: f32 = @floatFromInt(self.window_size.h);
    const banner_h = text_h + self.options.padding_y * 2.0;
    const top = fh - self.options.margin_bottom - banner_h;
    self.rect_top = top;
    self.rect_height = banner_h;

    // 容器尺寸变化 → 更新背景 uniform（普通 uniform，代价可忽略）
    self.background.update(self.window_size, top, banner_h, self.options.color.value(), self.options.debug);

    // 文字在容器内居中
    t.position(.{
        .x = (fw - text_w) * 0.5,
        .y = top + (banner_h - text_h) * 0.5,
    }).debug(self.options.debug);

    // 立即生成文字的渲染依赖并提交上传
    _ = try t.toWidget(self.uploader, self.window_size, self.text_pipeline);
    try self.uploader.submit();
}

/// 设置背景色。
pub fn setColor(self: *Self, color: Color) void {
    self.options.color = color;
    self.background.update(self.window_size, self.rect_top, self.rect_height, color.value(), self.options.debug);
}

/// 调试开关：为背景与文字叠加红色。
pub fn debug(self: *Self, value: bool) *Self {
    self.options.debug = value;
    self.background.update(self.window_size, self.rect_top, self.rect_height, self.options.color.value(), value);
    if (self.text) |*t| t.debug(value);
    return self;
}

pub fn toWidget(self: *Self) Widget {
    return .{
        .ptr = @ptrCast(self),
        .vtable = Widget.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.background.draw(cmd, pass);
    if (self.text) |*t| t.draw(cmd, pass);
}

pub fn event(self: *Self, e: *const Event) void {
    const mouse_y = e.mouse_y;
    const is_hover = mouse_y >= self.rect_top and mouse_y <= (self.rect_top + self.rect_height);
    if (self.on_hover) |cb| if (is_hover != self.last_hover) {
        cb.call(is_hover);
        self.last_hover = is_hover;
    };
    if (self.on_click) |cb| if (is_hover and e.click == .down) cb.call({});
}
