const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const paths = @import("config/paths.zig");
pub const loader = @import("config/loader.zig");
pub const Error = @import("config/errors.zig").Error;
pub const Sort = loader.Sort;

var initialized: bool = false;
var cache: loader.Loaded = undefined;

pub fn init(allocator: Allocator, config_path: ?[]const u8) Error!void {
    cache = try loader.load(allocator, config_path);
    initialized = true;
}

pub fn deinit() void {
    if (!initialized) return;
    cache.deinit();
    cache = undefined;
    initialized = false;
}

pub inline fn get() *const loader.MainConfig {
    return cache.get();
}

/// 已解析且保证有效的 Mod 键，外部无需再做错误或空值处理
pub inline fn modKey() loader.ModKey {
    return cache.mod_key;
}

/// 已解析且保证有效的排序方式，外部无需再做错误或空值处理
pub inline fn sort() loader.Sort {
    return cache.sort;
}

/// 将配置目录和输入路径组合，创建完整路径。
/// 若输入路径为 `~` 或以 `~/` 开头，则展开为用户主目录下的绝对路径；
/// 若输入路径是绝对路径，将直接返回输入路径。
pub fn allocFullPath(allocator: Allocator, path: []const u8) Error![]const u8 {
    if (path.len > 0 and path[0] == '~' and (path.len == 1 or std.fs.path.isSep(path[1]))) {
        return try expandHome(allocator, path);
    }
    if (std.fs.path.isAbsolute(path)) {
        return try allocator.dupe(u8, path);
    }
    if (get().base_dir) |base_dir| {
        return try std.fs.path.join(allocator, &.{ base_dir, path });
    } else {
        return Error.ConfigNotFound;
    }
}

/// 将以 `~` 开头的路径展开为基于用户主目录的绝对路径。
fn expandHome(allocator: Allocator, path: []const u8) Error![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    var rest = path[1..];
    while (rest.len > 0 and std.fs.path.isSep(rest[0])) {
        rest = rest[1..];
    }
    if (rest.len == 0) return try allocator.dupe(u8, home);
    return try std.fs.path.join(allocator, &.{ home, rest });
}

/// 按平台选择用户主目录的解析实现（编译期计算，无需运行时分支）。
const getHomeDir = if (builtin.os.tag == .windows) getHomeDirWindows else getHomeDirPosix;

fn getHomeDirPosix(allocator: Allocator) Error![]u8 {
    return try std.process.getEnvVarOwned(allocator, "HOME");
}

fn getHomeDirWindows(allocator: Allocator) Error![]u8 {
    if (std.process.getEnvVarOwned(allocator, "USERPROFILE")) |profile| {
        if (profile.len > 0) return profile;
        allocator.free(profile);
    } else |err| {
        if (err != error.EnvironmentVariableNotFound) return err;
    }

    // 回退到旧式 HOMEDRIVE + HOMEPATH
    const drive = try std.process.getEnvVarOwned(allocator, "HOMEDRIVE");
    defer allocator.free(drive);
    const home_path = try std.process.getEnvVarOwned(allocator, "HOMEPATH");
    defer allocator.free(home_path);
    return try std.fs.path.join(allocator, &.{ drive, home_path });
}
