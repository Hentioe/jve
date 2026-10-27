const std = @import("std");
const Args = std.process.Args;
const Allocator = std.mem.Allocator;
const clap = @import("clap");

const io = std.Io.Threaded.global_single_threaded.io();
const params = clap.parseParamsComptime(
    \\-d, --display <str>
    \\-c, --config <str>
    \\--clear-dead-cache
    \\--supports
    \\<str>
);

pub fn init(allocator: Allocator, args: Args) !clap.Result(clap.Help, &params, clap.parsers.default) {
    var diag = clap.Diagnostic{};
    return clap.parse(clap.Help, &params, clap.parsers.default, args, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err;
    };
}
