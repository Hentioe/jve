pub const c = @import("ass/c.zig").c;
pub const h = @import("ass/helper.zig");
pub const Library = @import("ass/Library.zig");
pub const Renderer = @import("ass/Renderer.zig");
pub const Error = @import("ass/errors.zig").Error;

// -- 别名 --
pub const Track = c.ASS_Track;
pub const Image = c.ASS_Image;
