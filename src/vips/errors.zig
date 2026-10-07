const std = @import("std");

pub const VipsError = error{VipsFailed};

pub const CustomError = error{
    FormatsNotCached, // 格式未缓存
    UnsupportedFormat, // 不支持的格式
};

pub const Error = VipsError || CustomError || std.mem.Allocator.Error;
