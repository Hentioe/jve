const std = @import("std");
const c = @import("c.zig").c;

pub fn check(ort_api: *const c.OrtApi, expr: ?*c.OrtStatus) bool {
    if (expr) |status| {
        const err = ort_api.*.GetErrorMessage.?(status);
        std.log.err("[ORT ERROR] {s}", .{std.mem.span(err)});
        ort_api.*.ReleaseStatus.?(status);
    }

    return expr == null;
}
