const std = @import("std");

pub const CustomError = error{};
pub const Error = CustomError || std.process.GetEnvVarOwnedError;
