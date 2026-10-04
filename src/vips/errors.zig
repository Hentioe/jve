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
    UnsupportedChannels, // 不支持的通道数
};

pub const MallocError = error{
    MalloptFailed,
};

pub const Error = CustomError || VipsError || MallocError || std.mem.Allocator.Error;
