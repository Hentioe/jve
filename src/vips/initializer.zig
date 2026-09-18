const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;

pub fn initialize() Error!void {
    if (c.vips_init("imageviewer") != 0) {
        helper.printError();
        return Error.VipsInitFailed;
    }
}
