const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const FrameSize = shared.Size2D(i32);
const icons = @import("icons.zig");
const AssRendered = @import("AssRendered.zig");
const icon_renderer = @import("icon_renderer.zig");
const BuildOptions = icon_renderer.Options;
const Window = @import("../display/window.zig");
const Pipeline = @import("../display/TextPipeline.zig");
const PipelineOptions = Pipeline.Options;
const Position = @import("shared").Point(f32);
const Drawable = @import("Drawable.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: Allocator,
raster: AssRendered,
pipeline: Pipeline = undefined,
pipeline_options: PipelineOptions,
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
        .pipeline_options = .{},
    };
}

pub fn deinit(self: *Self) void {
    if (self.is_drawable) self.pipeline.deinit();
    self.raster.deinit();
    self.* = undefined;
}

pub fn position(self: *Self, value: Position) *Self {
    self.pipeline_options.position = value;
    return self;
}

pub fn debug(self: *Self, value: bool) void {
    self.pipeline_options.debug = value;
}

pub fn toDrawable(self: *Self, window: *const Window, gpu: *const sdl.Gpu, frame_size: FrameSize) Error!Drawable {
    std.debug.assert(!self.is_drawable);
    self.pipeline = try Pipeline.init(
        self.allocator,
        window,
        gpu,
        frame_size,
        &self.raster,
        self.pipeline_options,
    );
    self.is_drawable = true;

    return .{
        .ptr = @ptrCast(self),
        .vtable = Drawable.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.pipeline.draw(pass, cmd);
}
