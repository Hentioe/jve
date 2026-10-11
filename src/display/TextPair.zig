const AssRendered = @import("../ui.zig").AssRendered;
const Options = @import("TextPipeline.zig").Options;
const Self = @This();

raster: *const AssRendered,
options: Options,

pub fn init(raster: *const AssRendered, options: Options) Self {
    return Self{
        .raster = raster,
        .options = options,
    };
}
