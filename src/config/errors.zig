const std = @import("std");

pub const CustomError = error{
    ParseError,
};
pub const Error = CustomError || std.mem.Allocator.Error || std.process.GetEnvVarOwnedError;
