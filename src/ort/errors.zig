const std = @import("std");
pub const OrtError = error{OrtFailed};

pub const Error = OrtError || std.mem.Allocator.Error;
