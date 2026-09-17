const std = @import("std");
const clap = @import("clap");

const params = clap.parseParamsComptime(
    \\<str>
    \\-b, --backend <str>
    \\
);

pub fn init(allocator: std.mem.Allocator) !clap.Result(clap.Help, &params, clap.parsers.default) {
    var diag = clap.Diagnostic{};
    return clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try diag.reportToFile(.stderr(), err);
        return err;
    };
}
