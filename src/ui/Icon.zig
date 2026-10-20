const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const FrameSize = shared.Size2D(i32);
const icons = @import("icons.zig");
const AssRendered = @import("AssRendered.zig");
const icon_renderer = @import("icon_renderer.zig");
const BuildOptions = icon_renderer.Options;
const TextPipeline = @import("TextPipeline.zig");
const TextDrawer = @import("TextDrawer.zig");
const LayoutOptions = @import("options.zig").LayoutOptions;
const Position = @import("shared").Point(f32);
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
raster: AssRendered,
options: LayoutOptions = .{},
drawer: TextDrawer = undefined,
is_drawable: bool = false,

pub const IconType = enum {
    close,
    minimize,
    image,

    pub fn value(self: IconType) []const u8 {
        return switch (self) {
            .close => icons.close,
            .minimize => icons.minimize,
            .image => icons.image,
        };
    }
};

pub fn init(allocator: Allocator, icon_type: IconType, options: BuildOptions) Error!Self {
    const raster = try icon_renderer.render(allocator, icon_type.value(), options);
    return Self{
        .allocator = allocator,
        .raster = raster,
    };
}

pub fn deinit(self: *Self) void {
    if (self.is_drawable) self.drawer.deinit();
    self.raster.deinit();
    self.* = undefined;
}

pub fn position(self: *Self, value: Position) *Self {
    self.options.position = value;
    return self;
}

pub fn debug(self: *Self, value: bool) void {
    self.options.debug = value;
}

pub fn toWidget(self: *Self, frame_size: FrameSize, pipeline: *TextPipeline) Error!Widget {
    std.debug.assert(!self.is_drawable);
    self.drawer = try TextDrawer.init(self.allocator, pipeline, frame_size, &self.raster, self.options);
    self.is_drawable = true;

    return .{
        .ptr = @ptrCast(self),
        .vtable = Widget.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.drawer.draw(cmd, pass);
}

pub fn event(_: *Self, _: *const Event) void {
    // todo: 增加 hover 事件
}
