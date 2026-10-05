const std = @import("std");

pub const ConfigError = error{
    ConfigParseError,
    ConfigNotFound,
};
pub const Error = ConfigError || std.mem.Allocator.Error || std.process.GetEnvVarOwnedError;
