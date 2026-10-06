const std = @import("std");

pub const VipsError = error{
    VipsInitFailed,
    VipsHeifLoadFailed,
    VipsAddAlphaFailed,
    VipsForeignGetSuffixesFailed,
    VipsImageLoadFailed,
    VipsEncodingFailed,
    VipsResizeFailed,
    VipsLinear1Failed,
    VipsFlattenFailed,
    VipsImageNewFromMemoryFailed,
    VipsBandJoinConst2Failed,
    VipsBandJoinFailed,
    VipsWriteToMemoryFailed,
    VipsWriteToFileFailed,
};

pub const CustomError = error{
    FormatsNotCached, // 格式未缓存
    UnsupportedFormat, // 不支持的格式
};

pub const Error = CustomError || VipsError || std.mem.Allocator.Error;
