const std = @import("std");
const KeybindingError = @import("Keybinding.zig").Error;

pub const CustomError = error{
    ConfigParseFailed,
    ConfigNotFound,
    BiRefNetVariantInvalid, // BiRefNet 变体无效（配置字段的值无效）
};

pub const Error = CustomError || KeybindingError || std.mem.Allocator.Error || std.process.GetEnvVarOwnedError;
