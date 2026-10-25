// 按 XDG Base Directory 规范查找配置文件。
// 查找优先级（从高到低）：
//
//   1. $XDG_CONFIG_HOME/<app>/<file>          （默认 ~/.config/<app>/<file>）
//   2. $XDG_CONFIG_DIRS 中各目录/<app>/<file>  （默认 /etc/xdg，多个目录用 ':' 分隔）
//
const std = @import("std");
const errors = @import("errors.zig");
const xdg = @import("xdg");
const app_env = @import("../app_env.zig");
const fs = std.fs;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Error = errors.Error;

const io = std.Io.Threaded.global_single_threaded.io();

/// 一条候选路径及来源
pub const Candidate = struct {
    path: []const u8,
    source: []const u8, // 例如 "XDG_CONFIG_HOME" 或 "XDG_CONFIG_DIRS"
};

/// 按优先级依次检查候选路径，返回第一个存在的文件路径（找不到则返回 null）。
/// 返回值由调用者负责 free。
pub fn findConfigFile(allocator: Allocator, app_name: []const u8, file_name: []const u8) Error!?[]u8 {
    const candidates = try listCandidates(allocator, app_name, file_name);
    defer freeCandidates(allocator, candidates);

    for (candidates) |c| {
        Io.Dir.accessAbsolute(io, c.path, .{}) catch continue;
        return try allocator.dupe(u8, c.path);
    }
    return null;
}

/// 按优先级列出所有候选路径（不检查是否存在）。
/// 返回的 []Candidate 及其内部 path 字符串都由调用者用 freeCandidates 释放。
pub fn listCandidates(allocator: Allocator, app_name: []const u8, file_name: []const u8) Error![]Candidate {
    var list = try std.ArrayList(Candidate).initCapacity(allocator, 0);
    errdefer {
        for (list.items) |c| allocator.free(c.path);
        list.deinit(allocator);
    }

    // 1. 用户层：$XDG_CONFIG_HOME/<app>/<file>
    const config_home = try xdg.getConfigHomeOwned(allocator);
    defer allocator.free(config_home);
    const user_path = try fs.path.join(allocator, &.{ config_home, app_name, file_name });
    try list.append(allocator, .{ .path = user_path, .source = "XDG_CONFIG_HOME" });

    // 2. 系统层：$XDG_CONFIG_DIRS 中各目录/<app>/<file>
    const dirs = try getConfigDirs(allocator);
    defer freeConfigDirs(allocator, dirs);
    for (dirs) |dir| {
        const p = try fs.path.join(allocator, &.{ dir, app_name, file_name });
        try list.append(allocator, .{ .path = p, .source = "XDG_CONFIG_DIRS" });
    }

    return list.toOwnedSlice(allocator);
}

/// 读取 $XDG_CONFIG_DIRS（':' 分隔），未设置则回退为 ["/etc/xdg"]。
/// 返回的 slice 及其中每个字符串都需要调用者释放（用 freeConfigDirs）。
pub fn getConfigDirs(allocator: Allocator) Error![][]u8 {
    var list = try std.ArrayList([]u8).initCapacity(allocator, 0);
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }

    if (try app_env.reader().getEnvVarOwned(allocator, "XDG_CONFIG_DIRS")) |val| {
        defer allocator.free(val);
        var it = std.mem.splitScalar(u8, val, ':');
        while (it.next()) |dir| {
            if (dir.len == 0) continue;
            try list.append(allocator, try allocator.dupe(u8, dir));
        }
    }

    if (list.items.len == 0) {
        try list.append(allocator, try allocator.dupe(u8, "/etc/xdg"));
    }

    return list.toOwnedSlice(allocator);
}

pub fn freeConfigDirs(allocator: Allocator, dirs: [][]u8) void {
    for (dirs) |d| allocator.free(d);
    allocator.free(dirs);
}

pub fn freeCandidates(allocator: Allocator, candidates: []Candidate) void {
    for (candidates) |c| allocator.free(c.path);
    allocator.free(candidates);
}
