const std = @import("std");
const vips = @import("vips.zig");

pub const CustomError = error{
    NotAFile,
};

pub const LoadError = CustomError || std.fs.File.OpenError || vips.Error;
