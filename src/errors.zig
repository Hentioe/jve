const std = @import("std");
const vips = @import("vips.zig");

pub const CustomError = error{NotAFile};
pub const SizeError = error{Negative};
pub const LoadError = CustomError || vips.Error || std.fs.File.OpenError;
