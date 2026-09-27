const std = @import("std");

pub const VipsError = error{
    VipsInitFailed,
    VipsHeifLoadFailed,
    VipsAddAlphaFailed,
    VipsForeignGetSuffixesFailed,
    VipsImageLoadFailed,
    VipsWriteFailed,
    VipsEncodingFailed,
    VipsResizeFailed,
    VipsLinear1Failed,
    VipsFlattenFailed,
    VipsBandJoinConst2Failed,
};

pub const CustomError = error{
    UnsupportedFormat, // 不支持的格式
    UnsupportedBands, // 不支持的通道数量
};

pub const Error = CustomError || VipsError || std.mem.Allocator.Error;
