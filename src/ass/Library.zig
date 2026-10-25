const c = @import("ass_c");
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

ass_library: *c.ASS_Library,

pub fn init() Error!Self {
    return Self{
        .ass_library = try h.check(c.ass_library_init()),
    };
}

pub fn deinit(self: *Self) void {
    c.ass_library_done(self.ass_library);
}

pub fn newTrack(self: *const Self) *c.ASS_Track {
    return c.ass_new_track(self.ass_library);
}

pub fn allocStyle(track: *c.ASS_Track) c_int {
    return c.ass_alloc_style(track);
}

pub fn allocEvent(track: *c.ASS_Track) c_int {
    return c.ass_alloc_event(track);
}
