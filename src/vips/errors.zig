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
    NotInitialized, // 未初始化
    UnsupportedFormat, // 不支持的格式
    UnsupportedBands, // 不支持的通道数量
};

pub const Error = CustomError || VipsError || std.mem.Allocator.Error;
