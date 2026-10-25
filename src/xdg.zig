// 按 XDG Base Directory 规范解析用户目录，供配置与缓存等模块复用。
const std = @import("std");
const Environ = std.process.Environ;
const Allocator = std.mem.Allocator;

pub const CustomError = error{HomeEnvironmentVariableNotFound};
pub const Error = CustomError || Allocator.Error;

var environ_map: *const Environ.Map = undefined;
var initialized: bool = false;

pub fn init(environ: *const Environ.Map) void {
    if (initialized) return;
    environ_map = environ;
    initialized = true;
}

/// 读取 `$XDG_CACHE_HOME`，未设置则回退为 `$HOME/.cache`。
pub fn getCacheHomeOwned(allocator: Allocator) Error![]u8 {
    return getEnvOrHomeDirOwned(allocator, "XDG_CACHE_HOME", ".cache");
}

/// 读取 `$XDG_CONFIG_HOME`，未设置则回退为 `$HOME/.config`。
pub fn getConfigHomeOwned(allocator: Allocator) Error![]u8 {
    return getEnvOrHomeDirOwned(allocator, "XDG_CONFIG_HOME", ".config");
}

fn getEnvOrHomeDirOwned(allocator: Allocator, env: []const u8, fallback: []const u8) Error![]u8 {
    if (getEnvVar(env)) |val| if (val.len > 0) return allocator.dupe(u8, val);
    // 空路径视为未设置，走 HOME 回退
    const home = getEnvVar("HOME") orelse return Error.HomeEnvironmentVariableNotFound;
    return std.fs.path.join(allocator, &.{ home, fallback });
}

fn getEnvVar(name: []const u8) ?[]const u8 {
    return environ_map.get(name);
}
