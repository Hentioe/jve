const std = @import("std");
const c = @import("ass_c");
const h = @import("helper.zig");
const Library = @import("Library.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

library: *const Library,
ass_renderer: *c.ASS_Renderer,

pub fn init(library: *const Library) Error!Self {
    return Self{
        .library = library,
        .ass_renderer = try h.check(c.ass_renderer_init(library.ass_library)),
    };
}

pub fn deinit(self: *Self, tag: []const u8) void {
    std.log.debug("Deinitializing ass renderer ({s})", .{tag});
    c.ass_renderer_done(self.ass_renderer);
}

pub fn setFonts(self: *const Self, default_font: [*c]const u8, default_family: [*c]const u8, dfp: c_int, config: [*c]const u8, update: c_int) void {
    c.ass_set_fonts(self.ass_renderer, default_font, default_family, dfp, config, update);
}

pub fn setFrameSize(self: *const Self, width: c_int, height: c_int) void {
    c.ass_set_frame_size(self.ass_renderer, width, height);
}

pub fn renderFrame(self: *const Self, track: *c.ASS_Track, now: c_longlong, detect_change: *c_int) ?*c.ASS_Image {
    return c.ass_render_frame(self.ass_renderer, track, now, detect_change);
}
