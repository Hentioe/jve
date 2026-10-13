const std = @import("std");
const ass = @import("ass");
const DisplayError = @import("../display/errors.zig").Error;

pub const Error = error{AssNotRendered} || ass.Error || DisplayError || std.mem.Allocator.Error;
