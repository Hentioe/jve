const std = @import("std");
const ass = @import("ass");

pub const Error = error{} || ass.Error || std.mem.Allocator.Error;
