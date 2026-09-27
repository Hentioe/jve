const std = @import("std");
const vips = @import("vips.zig");

pub const CustomLoadError = error{
    NotAFile,
};

pub const LoadError = CustomLoadError || std.fs.File.OpenError || vips.Error;
