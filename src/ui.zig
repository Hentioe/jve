const IconRenderer = @import("ui/IconRenderer.zig");
const Error = @import("ui/errors.zig").Error;

pub const text_renderer = @import("ui/text_renderer.zig");
pub const icon_renderer = @import("ui/icon_renderer.zig");
pub const Text = @import("ui/Text.zig");
pub const Icon = @import("ui/Icon.zig");
pub const icons = @import("ui/icons.zig");
pub const AssRendered = @import("ui/AssRendered.zig");
pub const AssLibrary = @import("ui/AssLibrary.zig");
pub const LayoutOptions = @import("ui/options.zig").LayoutOptions;
pub const TextPipeline = @import("ui/TextPipeline.zig");

pub fn init() Error!void {
    try IconRenderer.init();
}

pub fn deinit() void {
    IconRenderer.deinit();
    AssLibrary.deinit();
}
