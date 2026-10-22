// 用户着色器的编译缓存。
//
// 缓存目录位于 XDG 规范的 `~/.cache/jve/shaders/`：
//   - `manifest.json`：摘要文件，记录每个源码的 mtime、size、hash；
//   - `<hash>.spv`：编译产物，以源码内容哈希命名，内容相同即共享。
//
// 失效判定：先比对 mtime + size（低成本），任一变化再比对内容 hash，
// hash 也不同才重新编译。manifest 以原子方式写入，读取失败直接报错。
//
// `init` 会在格式/profile 不匹配时丢弃全部条目；`load` 只负责读取，
// 保留磁盘上记录的版本、profile 和全部条目，供调用方自行判断（如 cleaner）。
const std = @import("std");
const xdg = @import("xdg");
const consts = @import("consts.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Error = @import("errors.zig").Error;
const Cache = @This();

/// 单个着色器的摘要信息（manifest 中的条目）。
pub const Entry = struct {
    mtime: i128, // 源码修改时间（纳秒）
    size: u64, // 源码字节数，与 mtime 一同用于快速判定
    hash: u64, // 源码内容哈希（Wyhash）
};

/// 硬盘上的摘要结构。
const Wire = struct {
    version: u32,
    profile: []const u8,
    entries: []WireEntry,
};

const WireEntry = struct {
    name: []const u8,
    mtime: i128,
    size: u64,
    hash: u64,
};

gpa: Allocator,
arena: ArenaAllocator,
/// 缓存目录（位于 arena 中）。
dir_path: []const u8,
/// 当前编译环境标识（如 slang 的编译 profile），`save` 时写入摘要。
profile: []const u8,
/// 摘要中记录的格式版本；未读到摘要时为 0。
manifest_version: u32 = 0,
/// 摘要中记录的 profile（可能是旧的），未读到摘要时为空。
manifest_profile: []const u8 = "",
/// 是否成功读到了摘要文件。
has_manifest: bool = false,
/// 已有摘要，键为源码文件名（或路径），值为其摘要（键由 arena 持有）。
entries: std.StringArrayHashMapUnmanaged(Entry) = .empty,
dirty: bool = false,

pub fn init(gpa: Allocator, profile: []const u8) Error!Cache {
    var self = try load(gpa, profile);
    errdefer self.deinit();

    std.fs.cwd().makePath(self.dir_path) catch |err| {
        std.log.err("Failed to create shader cache directory {s}: {s}", .{ self.dir_path, @errorName(err) });
        return Error.CacheDirCreationFailed;
    };

    self.invalidateIfStale();
    return self;
}

/// 仅从磁盘读取摘要，不做格式/profile 校验，也不创建缓存目录。
///
/// 与 `init` 的区别：`init` 校验失败时丢弃全部条目；本函数原样返回摘要中的
/// `manifest_version`、`manifest_profile` 和所有条目，供需要自行判断旧缓存
/// （例如 cleaner）的调用方使用。摘要不存在时返回空缓存且 `has_manifest` 为 false。
pub fn load(gpa: Allocator, profile: []const u8) Error!Cache {
    var arena = ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const a = arena.allocator();

    const home = try xdg.getCacheHome(a);
    const dir_path = try std.fs.path.join(a, &.{ home, consts.CACHE_APP, consts.CACHE_SUBDIR });

    var self = Cache{
        .gpa = gpa,
        .arena = arena,
        .dir_path = dir_path,
        .profile = profile,
    };
    try self.loadManifest();
    return self;
}

/// 按 `profile` 与 `consts.FORMAT_VERSION` 校验已加载的摘要，
/// 不匹配时清空内存中的条目（磁盘内容不动）。
fn invalidateIfStale(self: *Cache) void {
    if (!self.has_manifest) return;
    if (self.manifest_version == consts.FORMAT_VERSION and std.mem.eql(u8, self.manifest_profile, self.profile)) return;

    std.log.warn("Shader cache format/profile changed", .{});
    self.entries.clearRetainingCapacity();
}

pub fn deinit(self: *Cache) void {
    self.arena.deinit();
    self.* = undefined;
}

pub fn get(self: *const Cache, name: []const u8) ?Entry {
    return self.entries.get(name);
}

/// 内容未变、仅元数据变化时刷新摘要（并标记为需要写回）。
pub fn touch(self: *Cache, name: []const u8, mtime: i128, size: u64) void {
    if (self.entries.getPtr(name)) |entry| {
        if (entry.mtime != mtime or entry.size != size) {
            entry.mtime = mtime;
            entry.size = size;
            self.dirty = true;
        }
    }
}

/// 读取缓存中的 SPIR-V；摘要不存在或缓存文件不存在时返回 null。
pub fn readSpv(self: *Cache, allocator: Allocator, name: []const u8) Error!?[]u8 {
    const entry = self.entries.get(name) orelse return null;
    const path = try self.spvPath(allocator, entry.hash);
    defer allocator.free(path);

    return std.fs.cwd().readFileAlloc(allocator, path, consts.MAX_SPV_SIZE) catch |err| switch (err) {
        error.FileNotFound => null,
        else => {
            std.log.err("Failed to read cached shader '{s}': {s}", .{ path, @errorName(err) });
            return Error.CacheReadFailed;
        },
    };
}

/// 写入新编译的 SPIR-V 并更新摘要。
pub fn write(self: *Cache, allocator: Allocator, name: []const u8, bytes: []const u8, mtime: i128, size: u64, hash: u64) Error!void {
    const path = try self.spvPath(allocator, hash);
    defer allocator.free(path);
    try atomicWrite(allocator, path, bytes);

    const a = self.arena.allocator();
    const owned = try a.dupe(u8, name);
    try self.entries.put(a, owned, .{ .mtime = mtime, .size = size, .hash = hash });
    self.dirty = true;
}

/// 原子地写回摘要文件（仅在内容变化时）。
pub fn save(self: *Cache) Error!void {
    if (!self.dirty) return;

    const gpa = self.gpa;
    var list = std.ArrayList(WireEntry).empty;
    defer list.deinit(gpa);

    var it = self.entries.iterator();
    while (it.next()) |kv| {
        try list.append(gpa, .{
            .name = kv.key_ptr.*,
            .mtime = kv.value_ptr.mtime,
            .size = kv.value_ptr.size,
            .hash = kv.value_ptr.hash,
        });
    }

    const wire = Wire{ .version = consts.FORMAT_VERSION, .profile = self.profile, .entries = list.items };
    var out: std.io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    std.json.Stringify.value(wire, .{ .whitespace = .indent_2 }, &out.writer) catch |err| {
        std.log.err("Failed to serialize shader cache manifest: {s}", .{@errorName(err)});
        return Error.CacheWriteFailed;
    };

    const a = self.arena.allocator();
    const path = std.fs.path.join(a, &.{ self.dir_path, consts.MANIFEST_NAME }) catch return Error.CacheWriteFailed;
    try atomicWrite(gpa, path, out.written());
    self.dirty = false;
}

fn loadManifest(self: *Cache) Error!void {
    const a = self.arena.allocator();
    const path = try std.fs.path.join(a, &.{ self.dir_path, consts.MANIFEST_NAME });

    const raw = std.fs.cwd().readFileAlloc(a, path, consts.MAX_MANIFEST_SIZE) catch |err| switch (err) {
        error.FileNotFound => return, // 首次加载，缓存为空
        else => {
            std.log.err("Failed to read shader cache manifest {s}: {s}", .{ path, @errorName(err) });
            return Error.CacheReadFailed;
        },
    };

    var parsed = std.json.parseFromSlice(Wire, self.gpa, raw, .{}) catch |err| {
        std.log.err("Failed to parse shader cache manifest {s}: {s}", .{ path, @errorName(err) });
        return Error.CacheParseFailed;
    };
    defer parsed.deinit();

    // 记录摘要来源；是否可用由调用方（init/cleaner 等）判断
    self.manifest_version = parsed.value.version;
    self.manifest_profile = try a.dupe(u8, parsed.value.profile);
    self.has_manifest = true;

    for (parsed.value.entries) |e| {
        if (e.name.len == 0) continue;
        const name = try a.dupe(u8, e.name);
        try self.entries.put(a, name, .{ .mtime = e.mtime, .size = e.size, .hash = e.hash });
    }
}

fn spvPath(self: *const Cache, allocator: Allocator, hash: u64) Error![]u8 {
    const fname = try spvName(allocator, hash);
    defer allocator.free(fname);
    return std.fs.path.join(allocator, &.{ self.dir_path, fname });
}

/// 由源码内容哈希推导编译产物名，与 manifest 中的 hash 字段文本一致。
fn spvName(allocator: Allocator, hash: u64) Error![]u8 {
    return std.fmt.allocPrint(allocator, "{d}.spv", .{hash});
}

const testing = std.testing;

fn testCache(arena: *ArenaAllocator, dir: []const u8, profile: []const u8) Error!Cache {
    const owned = try arena.allocator().dupe(u8, dir);
    var cache = Cache{
        .gpa = testing.allocator,
        .arena = arena.*,
        .dir_path = owned,
        .profile = profile,
    };
    errdefer cache.deinit();
    try cache.loadManifest();
    return cache;
}

test "spvName" {
    const a = testing.allocator;
    const one = try spvName(a, 0x0123456789abcdef);
    defer a.free(one);
    try testing.expectEqualStrings("81985529216486895.spv", one);

    const two = try spvName(a, 42);
    defer a.free(two);
    try testing.expectEqualStrings("42.spv", two);
}

test "write, save, reload round trip" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);

    {
        var arena: ArenaAllocator = .init(testing.allocator);
        var cache = try testCache(&arena, dir, "spirv_1_5");
        defer cache.deinit();

        const bytes = "spirv-bytes";
        try cache.write(testing.allocator, "foo.frag.slang", bytes, 123, 45, 999);
        try cache.save();

        const got = (try cache.readSpv(testing.allocator, "foo.frag.slang")).?;
        defer testing.allocator.free(got);
        try testing.expectEqualStrings(bytes, got);
    }

    // 重新打开：摘要应已持久化
    var arena: ArenaAllocator = .init(testing.allocator);
    var cache = try testCache(&arena, dir, "spirv_1_5");
    defer cache.deinit();

    const entry = cache.get("foo.frag.slang").?;
    try testing.expectEqual(@as(i128, 123), entry.mtime);
    try testing.expectEqual(@as(u64, 45), entry.size);
    try testing.expectEqual(@as(u64, 999), entry.hash);
}

test "profile change invalidates cache" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);

    {
        var arena: ArenaAllocator = .init(testing.allocator);
        var cache = try testCache(&arena, dir, "spirv_1_5");
        defer cache.deinit();
        try cache.write(testing.allocator, "foo.frag.slang", "x", 1, 2, 3);
        try cache.save();
    }

    // profile 不同：init 的校验会丢弃全部条目（这里手动模拟该步骤）
    var arena: ArenaAllocator = .init(testing.allocator);
    var cache = try testCache(&arena, dir, "spirv_1_6");
    defer cache.deinit();
    cache.invalidateIfStale();
    try testing.expect(cache.get("foo.frag.slang") == null);
}

test "load keeps entries and old profile" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);

    {
        var arena: ArenaAllocator = .init(testing.allocator);
        var cache = try testCache(&arena, dir, "spirv_1_5");
        defer cache.deinit();
        try cache.write(testing.allocator, "foo.frag.slang", "x", 1, 2, 3);
        try cache.save();
    }

    // 只加载、不校验：旧 profile 与条目都应原样保留
    var arena: ArenaAllocator = .init(testing.allocator);
    var cache = try testCache(&arena, dir, "spirv_1_6");
    defer cache.deinit();

    try testing.expect(cache.has_manifest);
    try testing.expectEqual(consts.FORMAT_VERSION, cache.manifest_version);
    try testing.expectEqualStrings("spirv_1_5", cache.manifest_profile);
    try testing.expect(cache.get("foo.frag.slang") != null);
}

test "no manifest leaves cache empty" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);

    var arena: ArenaAllocator = .init(testing.allocator);
    var cache = try testCache(&arena, dir, "spirv_1_5");
    defer cache.deinit();

    try testing.expect(!cache.has_manifest);
    try testing.expectEqual(@as(usize, 0), cache.entries.count());
}

test "missing spv returns null" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir);

    var arena: ArenaAllocator = .init(testing.allocator);
    var cache = try testCache(&arena, dir, "spirv_1_5");
    defer cache.deinit();
    try testing.expect((try cache.readSpv(testing.allocator, "none.frag.slang")) == null);
}

/// 先写临时文件再重命名，避免写入中断留下损坏的缓存。
fn atomicWrite(allocator: Allocator, path: []const u8, bytes: []const u8) Error!void {
    const tmp = std.fmt.allocPrint(allocator, "{s}.tmp", .{path}) catch return Error.CacheWriteFailed;
    defer allocator.free(tmp);

    {
        var file = std.fs.cwd().createFile(tmp, .{}) catch |err| {
            std.log.err("Failed to create cache file '{s}': {s}", .{ tmp, @errorName(err) });
            return Error.CacheWriteFailed;
        };
        defer file.close();
        file.writeAll(bytes) catch |err| {
            std.log.err("Failed to write cache file '{s}': {s}", .{ tmp, @errorName(err) });
            return Error.CacheWriteFailed;
        };
    }

    std.fs.cwd().rename(tmp, path) catch |err| {
        std.log.err("Failed to rename cache file '{s}' -> '{s}': {s}", .{ tmp, path, @errorName(err) });
        return Error.CacheWriteFailed;
    };
}
