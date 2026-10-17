const std = @import("std");
const ass = @import("ass");
const DisplayError = @import("../display/errors.zig").Error;

pub const CustomError = error{AssNotRendered} || ass.Error || std.mem.Allocator.Error;
pub const Error = CustomError || DisplayError; // todo: 移除 DisplayError
