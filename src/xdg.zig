// 按 XDG Base Directory 规范解析用户目录，供配置与缓存等模块复用。
const std = @import("std");
const Allocator = std.mem.Allocator;
const GetEnvVarOwnedError = std.process.GetEnvVarOwnedError;

pub const Error = Allocator.Error || GetEnvVarOwnedError;

/// 读取 `$XDG_CACHE_HOME`，未设置则回退为 `$HOME/.cache`。
pub fn getCacheHome(allocator: Allocator) Error![]u8 {
    return getEnvDirOrHome(allocator, "XDG_CACHE_HOME", ".cache");
}

/// 读取 `$XDG_CONFIG_HOME`，未设置则回退为 `$HOME/.config`。
pub fn getConfigHome(allocator: Allocator) Error![]u8 {
    return getEnvDirOrHome(allocator, "XDG_CONFIG_HOME", ".config");
}

fn getEnvDirOrHome(allocator: Allocator, env: []const u8, fallback: []const u8) Error![]u8 {
    if (std.process.getEnvVarOwned(allocator, env)) |val| {
        if (val.len > 0) return val;
        allocator.free(val); // 空路径视为未设置，走回退
    } else |err| {
        if (err != GetEnvVarOwnedError.EnvironmentVariableNotFound) return err;
    }

    const home = try std.process.getEnvVarOwned(allocator, "HOME");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, fallback });
}
