const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Size2D = shared.Size2D;
const AssRendered = @import("AssRendered.zig");
const text_renderer = @import("text_renderer.zig");
const BuildOptions = text_renderer.Options;
const Uploader = @import("../display/Uploader.zig");
const TextPipeline = @import("TextPipeline.zig");
const TextDrawer = @import("TextDrawer.zig");
const LayoutOptions = @import("options.zig").LayoutOptions;
const Position = @import("shared").Point(f32);
const Drawable = @import("Drawable.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
raster: AssRendered,
options: LayoutOptions = .{},
drawer: TextDrawer = undefined,
is_drawable: bool = false,

pub fn init(allocator: Allocator, renderer: *const ass.Renderer, value: []const u8, options: BuildOptions) Error!Self {
    const raster = try text_renderer.render(allocator, renderer, value, options);
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

pub fn toDrawable(self: *Self, uploader: *Uploader, frame_size: Size2D(i32), pipeline: *TextPipeline) Error!Drawable {
    std.debug.assert(!self.is_drawable);
    self.drawer = try TextDrawer.init(self.allocator, uploader, pipeline, frame_size, &self.raster, self.options);
    self.is_drawable = true;

    return .{
        .ptr = @ptrCast(self),
        .vtable = Drawable.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.drawer.draw(cmd, pass);
}
