const std = @import("std");
const Allocator = std.mem.Allocator;
const Self = @This();

pub const ScanError = error{};
pub const Error = ScanError || std.fs.Dir.OpenError || std.mem.Allocator.Error;

gpa: Allocator,
arena: std.heap.ArenaAllocator,
dir_path: []const u8,
extensions: []const []const u8,
names: std.ArrayList([]const u8),
index: usize,
wrap: bool,

pub const Options = struct {
    /// next/prev 到头时是否回绕；false 时返回 null 且位置不变。
    wrap: bool = true, // todo: 配置化
    // todo: 配置化更多，如：排序方式
};

pub fn init(gap: Allocator, dir_path: []const u8, extensions: []const []const u8) Error!Self {
    var self = Self{
        .gpa = gap,
        .arena = .init(gap),
        .dir_path = dir_path,
        .extensions = extensions,
        .names = .empty,
        .index = 0,
        .wrap = true,
    };
    errdefer self.deinit();
    // 初始化时立即扫描
    try self.scan();
    return self;
}

pub fn deinit(self: *Self) void {
    self.names.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}

pub fn scan(self: *Self) Error!void {
    self.names.clearRetainingCapacity();
    _ = self.arena.reset(.retain_capacity);
    self.index = 0;

    const a = self.arena.allocator();

    var dir = try std.fs.cwd().openDir(self.dir_path, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .file, .sym_link, .unknown => {},
            else => continue,
        }
        if (!matchExt(entry.name, self.extensions)) continue;

        const owned = try a.dupe(u8, entry.name);
        try self.names.append(self.gpa, owned);
    }

    // 输出文件数量
    std.log.info("Found {d} supported file(s)", .{self.names.items.len});
    // 按自然顺序排序文件名
    std.mem.sort([]const u8, self.names.items, {}, naturalLessThan);
}

pub fn next(self: *Self) ?[]const u8 {
    const n = self.names.items.len;
    if (n == 0) return null;
    if (self.index + 1 < n) {
        self.index += 1;
    } else if (self.wrap) {
        self.index = 0;
    } else {
        return null;
    }
    return self.names.items[self.index];
}

pub fn prev(self: *Self) ?[]const u8 {
    const n = self.names.items.len;
    if (n == 0) return null;
    if (self.index > 0) {
        self.index -= 1;
    } else if (self.wrap) {
        self.index = n - 1;
    } else {
        return null;
    }
    return self.names.items[self.index];
}

pub fn current(self: *const Self) ?[]const u8 {
    if (self.names.items.len == 0) return null;
    return self.names.items[self.index];
}

/// 重新扫描并尽量保持当前文件；当前文件已被删除时，位置钳制到原 index 附近。
pub fn rescan(self: *Self) !void {
    const old_index = self.index;
    const old_name: ?[]u8 = if (self.current()) |c| try self.gpa.dupe(u8, c) else null;
    defer if (old_name) |n| self.gpa.free(n);

    try self.scan();

    if (old_name) |n| {
        if (self.select(n)) return;
    }
    const len = self.names.items.len;
    self.index = if (len == 0) 0 else @min(old_index, len - 1);
}

/// 返回当前文件的完整路径，由调用方释放。
pub fn currentPathAlloc(self: *const Self, allocator: Allocator) !?[]u8 {
    const name = self.current() orelse return null;
    return try std.fs.path.join(allocator, &.{ self.dir_path, name });
}

/// 按文件名定位；找不到返回 false，位置不变。
pub fn select(self: *Self, name: []const u8) bool {
    for (self.names.items, 0..) |n, i| {
        if (std.mem.eql(u8, n, name)) {
            self.index = i;
            return true;
        }
    }
    return false;
}

pub fn count(self: *const Self) usize {
    return self.names.items.len;
}

pub fn position(self: *const Self) usize {
    return self.index;
}

pub fn basePath(self: *const Self) []const u8 {
    return self.dir_path;
}

pub fn items(self: *const Self) []const []const u8 {
    return self.names.items;
}

fn matchExt(name: []const u8, exts: []const []const u8) bool {
    if (exts.len == 0) return true;
    for (exts) |raw| {
        const want = if (raw.len > 0 and raw[0] == '.') raw[1..] else raw;
        if (want.len == 0) continue;
        if (name.len <= want.len + 1) continue;
        if (name[name.len - want.len - 1] != '.') continue;
        if (std.ascii.eqlIgnoreCase(name[name.len - want.len ..], want)) return true;
    }
    return false;
}

fn naturalLessThan(_: void, a: []const u8, b: []const u8) bool {
    return naturalOrder(a, b) == .lt;
}

/// 自然排序：忽略大小写，数字段按数值比较（img2 < img10），最后以字节序兜底保证全序。
fn naturalOrder(a: []const u8, b: []const u8) std.math.Order {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        const ca = a[i];
        const cb = b[j];
        if (std.ascii.isDigit(ca) and std.ascii.isDigit(cb)) {
            var si = i;
            while (si < a.len and a[si] == '0') si += 1;
            var sj = j;
            while (sj < b.len and b[sj] == '0') sj += 1;

            var ei = si;
            while (ei < a.len and std.ascii.isDigit(a[ei])) ei += 1;
            var ej = sj;
            while (ej < b.len and std.ascii.isDigit(b[ej])) ej += 1;

            const len_order = std.math.order(ei - si, ej - sj);
            if (len_order != .eq) return len_order;
            const num_order = std.mem.order(u8, a[si..ei], b[sj..ej]);
            if (num_order != .eq) return num_order;

            i = ei;
            j = ej;
        } else {
            const la = std.ascii.toLower(ca);
            const lb = std.ascii.toLower(cb);
            if (la != lb) return std.math.order(la, lb);
            i += 1;
            j += 1;
        }
    }
    const rest = std.math.order(a.len - i, b.len - j);
    if (rest != .eq) return rest;
    return std.mem.order(u8, a, b);
}

const testing = std.testing;

fn touch(dir: std.fs.Dir, name: []const u8) !void {
    const f = try dir.createFile(name, .{});
    f.close();
}

test "matchExt" {
    const exts = [_][]const u8{ "png", ".JPG", "tar.gz" };
    try testing.expect(matchExt("a.png", &exts));
    try testing.expect(matchExt("a.PNG", &exts));
    try testing.expect(matchExt("a.jpg", &exts));
    try testing.expect(matchExt("a.tar.gz", &exts));
    try testing.expect(!matchExt("a.gz", &exts));
    try testing.expect(!matchExt(".png", &exts));
    try testing.expect(!matchExt("apng", &exts));
    try testing.expect(!matchExt("a.gif", &exts));
    try testing.expect(matchExt("anything", &[_][]const u8{}));
}

test "naturalOrder" {
    try testing.expectEqual(std.math.Order.lt, naturalOrder("img2.png", "img10.png"));
    try testing.expectEqual(std.math.Order.lt, naturalOrder("a.png", "B.png"));
    try testing.expectEqual(std.math.Order.lt, naturalOrder("img01", "img1"));
    try testing.expectEqual(std.math.Order.gt, naturalOrder("img1", "img01"));
    try testing.expectEqual(std.math.Order.eq, naturalOrder("x", "x"));
}

test "scan, filter, sort, next/prev with wrap" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try touch(tmp.dir, "img10.png");
    try touch(tmp.dir, "img2.png");
    try touch(tmp.dir, "img1.PNG");
    try touch(tmp.dir, "notes.txt");
    try touch(tmp.dir, "pic.jpg");
    try tmp.dir.makeDir("sub.png");

    const path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(path);

    const exts = [_][]const u8{ "png", "jpg" };
    var s = try Self.init(testing.allocator, path, &exts, .{});
    defer s.deinit();

    try testing.expectEqual(@as(usize, 4), s.count());
    try testing.expectEqualStrings("img1.PNG", s.current().?);
    try testing.expectEqualStrings("img2.png", s.next().?);
    try testing.expectEqualStrings("img10.png", s.next().?);
    try testing.expectEqualStrings("pic.jpg", s.next().?);
    try testing.expectEqualStrings("img1.PNG", s.next().?);
    try testing.expectEqualStrings("pic.jpg", s.prev().?);

    const full = (try s.currentPathAlloc(testing.allocator)).?;
    defer testing.allocator.free(full);
    try testing.expect(std.mem.endsWith(u8, full, "pic.jpg"));
}

test "no wrap" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try touch(tmp.dir, "a.png");
    try touch(tmp.dir, "b.png");

    const path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(path);

    var s = try Self.init(testing.allocator, path, &.{"png"}, .{ .wrap = false });
    defer s.deinit();

    try testing.expect(s.prev() == null);
    try testing.expectEqualStrings("b.png", s.next().?);
    try testing.expect(s.next() == null);
    try testing.expectEqualStrings("b.png", s.current().?);
}

test "initFromFile + rescan keeps current" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try touch(tmp.dir, "a.png");
    try touch(tmp.dir, "b.png");
    try touch(tmp.dir, "c.png");

    const dir_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(dir_path);
    const file_path = try std.fs.path.join(testing.allocator, &.{ dir_path, "b.png" });
    defer testing.allocator.free(file_path);

    var s = try Self.initFromFile(testing.allocator, file_path, &.{"png"}, .{});
    defer s.deinit();
    try testing.expectEqualStrings("b.png", s.current().?);

    try touch(tmp.dir, "0.png");
    try s.rescan();
    try testing.expectEqual(@as(usize, 4), s.count());
    try testing.expectEqualStrings("b.png", s.current().?);

    try tmp.dir.deleteFile("b.png");
    try s.rescan();
    try testing.expectEqual(@as(usize, 3), s.count());
    try testing.expect(s.current() != null);
}

test "empty result" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try touch(tmp.dir, "a.txt");

    const path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(path);

    var s = try Self.init(testing.allocator, path, &.{"png"}, .{});
    defer s.deinit();
    try testing.expect(s.current() == null);
    try testing.expect(s.next() == null);
    try testing.expect(s.prev() == null);
}
