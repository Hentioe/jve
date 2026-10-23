const std = @import("std");

pub const CustomError = error{
    ConfigParseFailed,
    ConfigNotFound,
    BiRefNetVariantInvalid, // BiRefNet 变体无效（配置字段的值无效）
};
pub const Error = CustomError || std.mem.Allocator.Error || std.process.GetEnvVarOwnedError;
