const IconRenderer = @import("ui/IconRenderer.zig");
const Error = @import("ui/errors.zig").Error;

pub const Text = @import("ui/Text.zig");
pub const Icon = @import("ui/Icon.zig");
pub const icons = @import("ui/icons.zig");
pub const AssRendered = @import("ui/AssRendered.zig");
pub const AssLibrary = @import("ui/AssLibrary.zig");

pub fn init() Error!void {
    try IconRenderer.init();
}

pub fn deinit() void {
    IconRenderer.deinit();
    AssLibrary.deinit();
}
