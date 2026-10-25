const std = @import("std");

pub const SizeError = error{Negative};
pub const OpenUrlError = error{OpenUrlFailed} || std.process.SpawnError;
pub const Error = SizeError | OpenUrlError;
