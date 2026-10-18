const std = @import("std");

pub const SizeError = error{Negative};
pub const OpenUrlError = error{OpenUrlFailed} || std.process.Child.SpawnError;
pub const Error = SizeError | OpenUrlError;
