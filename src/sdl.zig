const errors = @import("sdl/errors.zig");

pub const c = @import("sdl/c.zig").c;
pub const h = @import("sdl/helper.zig");
pub const check = h.check;
pub const Gpu = @import("sdl/Gpu.zig");
pub const Renderer = @import("sdl/Renderer.zig");
pub const Error = errors.Error;
