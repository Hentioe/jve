const std = @import("std");
const xdg = @import("xdg");
const KeybindingError = @import("Keybinding.zig").Error;

pub const CustomError = error{
    ConfigParseFailed,
    ConfigNotFound,
    GetHomeDirFailed, // 获取用户主目录失败
    XdgConfigDirsNotFound, // $XDG_CONFIG_DIRS 没有找到
    BiRefNetVariantInvalid, // BiRefNet 变体无效（配置字段的值无效）
};

pub const Error = CustomError || KeybindingError || xdg.Error || std.mem.Allocator.Error;
