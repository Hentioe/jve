const std = @import("std");

pub const VipsError = error{VipsFailed};

pub const CustomError = error{
    FormatsNotCached, // 格式未缓存
    UnsupportedFormat, // 不支持的格式
    AnimationFrameIndex, // 动图帧索引越界
    AnimationFrameSize, // 动图帧尺寸与首帧不一致
    AnimationNoSource, // 动图源已释放，无法再解码新帧
};

pub const Error = VipsError || CustomError || std.mem.Allocator.Error;
