const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const FrameSize = shared.Size2D(i32);
const Position = shared.Point(f32);
const Icon = @import("Icon.zig");
const icon_renderer = @import("icon_renderer.zig");
const Uploader = @import("../display/Uploader.zig");
const TextPipeline = @import("TextPipeline.zig");
const RectPipeline = @import("RectPipeline.zig");
const RectDrawer = @import("RectDrawer.zig");
const Rect = RectDrawer.Rect;
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Color = @import("Color.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 包装 `Icon` 的按钮：图标在中间，四周留相等的边距，背景为可改色的纯色矩形。
///
/// 初始化只接收图标类型，`Icon` 的创建、配置与生命周期全部由内部管理。
/// 悬停/点击只触发回调，视觉反馈（如悬停变色）交由使用者（如 `TitleBar`）决定。
pub const Options = struct {
    /// 图标四周的等边距（像素）。
    padding: f32 = 6.0,
    /// 背景色（RGBA，0..1），默认全透明。
    color: Color = .rgba(0.0, 0.0, 0.0, 0.0),
    /// 内部图标组件的配置。
    icon: icon_renderer.Options = .{},
    /// 调试开关：为背景与图标叠加红色。
    debug: bool = false,
};

allocator: Allocator,
frame_size: FrameSize,
options: Options,
icon: Icon,
background: RectDrawer,
rect: Rect,

on_hover: ?Event.Callback(bool) = null,
on_click: ?Event.Callback(void) = null,

last_hover: bool = false,

pub fn init(
    allocator: Allocator,
    uploader: *Uploader,
    text_pipeline: *TextPipeline,
    rect_pipeline: *RectPipeline,
    frame_size: FrameSize,
    icon_type: Icon.IconType,
    position: Position,
    options: Options,
) Error!Self {
    var icon = try Icon.init(allocator, icon_type, options.icon);
    errdefer icon.deinit();
    icon.debug(options.debug);

    // 矩形尺寸 = 图标尺寸 + 四周等边距；图标在矩形内居中。
    const icon_size = icon.raster.size();
    const icon_w: f32 = @floatFromInt(icon_size.w);
    const icon_h: f32 = @floatFromInt(icon_size.h);
    const rect = Rect{
        .x = position.x,
        .y = position.y,
        .w = icon_w + options.padding * 2.0,
        .h = icon_h + options.padding * 2.0,
    };
    _ = icon.position(.{ .x = rect.x + options.padding, .y = rect.y + options.padding });

    var background = try RectDrawer.init(uploader, rect_pipeline, frame_size, rect, options.color.value(), options.debug);
    errdefer background.deinit();

    _ = try icon.toWidget(uploader, frame_size, text_pipeline);
    try uploader.submit();

    return Self{
        .allocator = allocator,
        .frame_size = frame_size,
        .options = options,
        .icon = icon,
        .background = background,
        .rect = rect,
    };
}

pub fn deinit(self: *Self) void {
    self.icon.deinit();
    self.background.deinit();
    self.* = undefined;
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
    self.icon.draw(cmd, pass);
}

pub fn event(self: *Self, e: *const Event) void {
    const inside = e.mouse_x >= self.rect.x and e.mouse_x <= (self.rect.x + self.rect.w) and
        e.mouse_y >= self.rect.y and e.mouse_y <= (self.rect.y + self.rect.h);
    if (inside != self.last_hover) {
        self.last_hover = inside;
        if (self.on_hover) |cb| cb.call(inside);
    }
    if (self.on_click) |cb| if (inside and e.click == .down) cb.call({});
}
