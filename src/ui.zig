const consts = @import("ui/consts.zig");
const IconRenderer = @import("ui/IconRenderer.zig");
const Error = @import("ui/errors.zig").Error;

pub const text_renderer = @import("ui/text_renderer.zig");
pub const icon_renderer = @import("ui/icon_renderer.zig");
pub const Widget = @import("ui/Widget.zig");
pub const Event = @import("ui/Event.zig");
pub const Color = @import("ui/Color.zig");
pub const Text = @import("ui/Text.zig");
pub const Icon = @import("ui/Icon.zig");
pub const icons = @import("ui/icons.zig");
pub const AssRendered = @import("ui/AssRendered.zig");
pub const AssLibrary = @import("ui/AssLibrary.zig");
pub const LayoutOptions = @import("ui/options.zig").LayoutOptions;
pub const TextPipeline = @import("ui/TextPipeline.zig");
pub const BannerPipeline = @import("ui/BannerPipeline.zig");
pub const RectPipeline = @import("ui/RectPipeline.zig");
pub const TextBanner = @import("ui/TextBanner.zig");
pub const Button = @import("ui/Button.zig");
pub const TitleBar = @import("ui/TitleBar.zig");
pub const CustomError = @import("ui/errors.zig").CustomError;

pub const DEFAULT_FONT = consts.DEFAULT_FONT;

pub fn init() Error!void {
    try IconRenderer.init();
}

pub fn deinit() void {
    IconRenderer.deinit();
    AssLibrary.deinit();
}
