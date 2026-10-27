const std = @import("std");
const c = @import("vips_c");
const h = @import("helper.zig");
const shared = @import("shared");
const consts = @import("consts.zig");
const Allocator = std.mem.Allocator;
const Image = @import("Image.zig");
const CString = shared.CString;
const Size2D = shared.Size2D;
const milliTimestamp = shared.milliTimestamp;
const Error = @import("errors.zig").Error;
const Self = @This();

const VIPS_ARGUMENT_NULL = consts.VIPS_ARGUMENT_NULL;

pub const Format = enum { gif, webp, jxl };

/// 缓存的填充方式：
/// - lazy：按需顺序抽取帧，缓存到上限后剩余帧使用临时缓冲；
/// - preload：初始化时一次性抽出全部帧，之后释放 roll。
pub const Mode = enum { lazy, preload };

pub const DEFAULT_CACHE_LIMIT: usize = 512 * 1024 * 1024;
const DEFAULT_DELAY_MS: u32 = 100;
const MIN_DELAY_MS: u32 = 10;

/// 临时诊断：首次抽帧的耗时只输出一次
var first_extract_logged = false;

pub const Options = struct {
    mode: Mode = .lazy,
    cache_limit_bytes: usize = DEFAULT_CACHE_LIMIT,
};

/// 指向容器内部像素数据的只读视图。
/// 已缓存的帧在整个容器生命周期内有效；未缓存的帧使用 scratch 缓冲，
/// 其指针只保证到下一次调用 `frameAt` / `next` 之前。
pub const FrameView = struct {
    index: usize,
    pixels: [*]const u8,
    len: usize,
    size: Size2D(u32),
};

allocator: std.mem.Allocator,
/// 文件路径（C 字符串，供重新打开 roll 使用）
path: CString,
format: Format,
mode: Mode,
width: i32,
page_height: i32,
count: usize,
/// 每帧显示时长（毫秒），索引与帧一一对应
delays_ms: []u32,
/// 累计 PTS（每帧的结束时间，毫秒），供播放阶段按时间定位帧
pts_ms: []u64,
total_ms: u64,
/// 从文件中读取的 loop 信息，仅用于展示，不参与播放控制
loop_count: u32,
/// 懒加载的 toilet roll；全部帧缓存后释放
roll: ?*c.VipsImage,
/// roll 中下一张尚未消费的页
next_seq: usize,
frames: []?Image.Out,
cached_count: usize,
cached_bytes: usize,
cache_limit_bytes: usize,
frame_bytes: usize,
/// 缓存达到上限后复用的临时帧
scratch: ?Image.Out,

/// 尝试把文件当作动图打开。不是 GIF/WebP/JXL、只有一帧或缺少 delay 元数据时返回 null。
pub fn init(allocator: Allocator, path: []const u8, options: Options) Error!?Self {
    const format = detectFormat(path) orelse return null;

    const c_path = try CString.fromPath(path);
    var roll: ?*c.VipsImage = null;
    var delays_ms: []u32 = &.{};
    var pts_ms: []u64 = &.{};
    var frames: []?Image.Out = &.{};
    var keep = false;
    defer if (!keep) {
        if (roll) |r| c.g_object_unref(r);
        if (delays_ms.len > 0) allocator.free(delays_ms);
        if (pts_ms.len > 0) allocator.free(pts_ms);
        if (frames.len > 0) {
            for (frames) |*slot| if (slot.*) |*out| out.deinit();
            allocator.free(frames);
        }
    };

    roll = try openRoll(c_path.data(), format);

    const width = c.vips_image_get_width(roll.?);
    const total_height = c.vips_image_get_height(roll.?);
    const page_height = c.vips_image_get_page_height(roll.?);
    const n_pages = c.vips_image_get_n_pages(roll.?);
    if (width <= 0 or page_height <= 0 or n_pages <= 1) return null;
    if (@as(i64, page_height) * @as(i64, n_pages) != total_height) {
        std.log.warn("Animation {f} has inconsistent page layout, treated as static", .{c_path});
        return null;
    }
    const count: usize = @intCast(n_pages);

    // delay 数组由 VipsImage 持有，必须在 roll 释放前复制出来。
    var delay_ptr: [*c]c_int = null;
    var delay_len: c_int = 0;
    if (c.vips_image_get_array_int(roll.?, "delay", &delay_ptr, &delay_len) != 0 or delay_len <= 0) {
        std.log.warn("Animation {f} has no frame delay metadata, treated as static", .{c_path});
        return null;
    }

    var loop: c_int = 0;
    if (c.vips_image_get_int(roll.?, "loop", &loop) != 0) loop = 0;
    const loop_count: u32 = if (loop > 0) @intCast(loop) else 0;

    delays_ms = try allocator.alloc(u32, count);
    pts_ms = try allocator.alloc(u64, count);
    frames = try allocator.alloc(?Image.Out, count);
    for (frames) |*slot| slot.* = null;

    var total_ms: u64 = 0;
    const readable_delays: usize = @intCast(delay_len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const raw: i64 = if (i < readable_delays) delay_ptr[i] else DEFAULT_DELAY_MS;
        const delay: u32 = if (raw <= 0)
            DEFAULT_DELAY_MS
        else if (raw < MIN_DELAY_MS)
            MIN_DELAY_MS
        else
            @intCast(raw);
        delays_ms[i] = delay;
        total_ms += delay;
        pts_ms[i] = total_ms;
    }

    const frame_bytes = @as(usize, @intCast(width)) * @as(usize, @intCast(page_height)) * 4;

    var self = Self{
        .allocator = allocator,
        .path = c_path,
        .format = format,
        .mode = options.mode,
        .width = width,
        .page_height = page_height,
        .count = count,
        .delays_ms = delays_ms,
        .pts_ms = pts_ms,
        .total_ms = total_ms,
        .loop_count = loop_count,
        .roll = roll,
        .next_seq = 0,
        .frames = frames,
        .cached_count = 0,
        .cached_bytes = 0,
        .cache_limit_bytes = options.cache_limit_bytes,
        .frame_bytes = frame_bytes,
        .scratch = null,
    };

    if (self.mode == .preload) {
        const total_bytes = std.math.mul(usize, self.frame_bytes, self.count) catch std.math.maxInt(usize);
        if (total_bytes > self.cache_limit_bytes) {
            std.log.warn(
                "Animation cache limit is too small for preload ({d} > {d}), falling back to lazy",
                .{ total_bytes, self.cache_limit_bytes },
            );
            self.mode = .lazy;
        } else {
            var index: usize = 0;
            while (index < self.count) : (index += 1) {
                _ = self.frameAt(index) catch |err| {
                    std.log.err("Failed to preload animation frame {d}: {}", .{ index, err });
                    self.mode = .lazy;
                    break;
                };
            }
        }
    }

    std.log.info(
        "Animation loaded: {s}, {d} frame(s), {d}x{d}, cache={s}, loop={d}",
        .{ std.fs.path.basename(self.path.data()), self.count, self.width, self.page_height, @tagName(self.mode), self.loop_count },
    );

    keep = true;
    return self;
}

pub fn deinit(self: *Self) void {
    for (self.frames) |*slot| {
        if (slot.*) |*out| out.deinit();
    }
    self.allocator.free(self.frames);
    if (self.scratch) |*out| out.deinit();
    self.allocator.free(self.delays_ms);
    self.allocator.free(self.pts_ms);
    self.releaseRoll();
    self.* = undefined;
}

/// 根据累计播放进度（毫秒）定位所在帧。
/// 进度可以超出总时长，内部会取模，因此天然支持无限循环。
pub fn frameIndexAt(self: *const Self, elapsed_ms: u64) usize {
    if (self.count == 0) return 0;
    const position = if (self.total_ms == 0) 0 else elapsed_ms % self.total_ms;
    return ptsIndex(self.pts_ms, position);
}

/// 取指定帧。已缓存时直接返回；否则从 roll 顺序抽取。
pub fn frameAt(self: *Self, index: usize) Error!FrameView {
    if (index >= self.count) return Error.AnimationFrameIndex;
    if (self.frames[index]) |*out| return self.view(index, out);

    // 没有 roll（已全部缓存，或上次解码失败）时重新打开。
    // 目标是已经过去的页时，roll 无法后退，同样重新打开。
    if (self.roll == null or index < self.next_seq) try self.reopenRoll();

    try self.extractAt(index);

    if (self.frames[index]) |*out| return self.view(index, out);
    if (self.scratch) |*out| return self.view(index, out);
    return Error.AnimationNoSource;
}

pub fn frameCount(self: *const Self) usize {
    return self.count;
}

pub fn totalMs(self: *const Self) u64 {
    return self.total_ms;
}

pub fn delayMs(self: *const Self, index: usize) u32 {
    if (index >= self.count) return 0;
    return self.delays_ms[index];
}

/// 仅作展示用途。播放控制完全由用户决定，不遵循该值。
pub fn loopCount(self: *const Self) u32 {
    return self.loop_count;
}

pub fn size(self: *const Self) Size2D(u32) {
    return .{ .w = @intCast(self.width), .h = @intCast(self.page_height) };
}

fn detectFormat(path: []const u8) ?Format {
    const extension = std.fs.path.extension(path);
    if (std.ascii.eqlIgnoreCase(extension, ".gif")) return .gif;
    if (std.ascii.eqlIgnoreCase(extension, ".webp")) return .webp;
    if (std.ascii.eqlIgnoreCase(extension, ".jxl")) return .jxl;
    return null;
}

fn openRoll(path: [:0]const u8, format: Format) Error!*c.VipsImage {
    var in: ?*c.VipsImage = null;
    // Animation 总是从第 0 页顺序向后读取，后退时会重新打开 roll。
    // 必须显式请求 sequential access：否则即使 loader 声明了
    // `VIPS_FOREIGN_SEQUENTIAL`（GIF、JXL，或打过补丁的 WebP），
    // `vips_foreign_load_temp()` 也会因为 access 是 random 而物化整条 roll。
    switch (format) {
        .gif => try h.check(c.vips_gifload(path, &in, "n", @as(c_int, -1), "access", c.VIPS_ACCESS_SEQUENTIAL, VIPS_ARGUMENT_NULL)),
        .webp => try h.check(c.vips_webpload(path, &in, "n", @as(c_int, -1), "access", c.VIPS_ACCESS_SEQUENTIAL, VIPS_ARGUMENT_NULL)),
        .jxl => try h.check(c.vips_jxlload(path, &in, "n", @as(c_int, -1), "access", c.VIPS_ACCESS_SEQUENTIAL, VIPS_ARGUMENT_NULL)),
    }
    return in.?;
}

fn reopenRoll(self: *Self) Error!void {
    self.releaseRoll();
    self.roll = try openRoll(self.path.data(), self.format);
    self.next_seq = 0;
}

fn releaseRoll(self: *Self) void {
    if (self.roll) |roll| {
        c.g_object_unref(roll);
        self.roll = null;
    }
}

fn extractAt(self: *Self, index: usize) Error!void {
    const roll = self.roll orelse return Error.AnimationNoSource;
    const top: c_int = @intCast(index * @as(usize, @intCast(self.page_height)));

    // 临时诊断：只输出首次抽帧的各阶段耗时，用于定位首次换帧的卡顿
    const log_first = !first_extract_logged;
    const started = milliTimestamp();
    if (log_first) std.log.debug("First animation frame decode started (index {d}/{d}, 0-based)", .{ index, self.count });

    var page: ?*c.VipsImage = null;
    try h.check(c.vips_crop(roll, &page, 0, top, self.width, self.page_height, VIPS_ARGUMENT_NULL));
    const cropped = milliTimestamp();

    // crop 出的页由 Image 接管所有权，转换完成后再转成连续内存。
    var image = Image.initFromVips(page.?);
    defer image.deinit();
    try image.toSrgb();
    const converted = milliTimestamp();
    try image.addAlpha(255.0);
    const alpha_added = milliTimestamp();

    if (image.width != self.width or image.height != self.page_height) return Error.AnimationFrameSize;

    // vips 管线是惰性的：crop/toSrgb/addAlpha 只建立管线，
    // 真正触发 roll 解码的是 write_to_memory（即下面的导出步骤）。
    var out = try image.allocOutInMemory();
    errdefer out.deinit();
    const written = milliTimestamp();

    if (log_first) {
        first_extract_logged = true;
        std.log.debug(
            "First animation frame decode took {d} ms (crop {d} ms, sRGB {d} ms, alpha {d} ms, write_to_memory {d} ms)",
            .{ written - started, cropped - started, converted - cropped, alpha_added - converted, written - alpha_added },
        );
    }

    self.next_seq = index + 1;

    if (self.cached_bytes + out.data_size <= self.cache_limit_bytes) {
        self.frames[index] = out;
        self.cached_bytes += out.data_size;
        self.cached_count += 1;
        // 全部帧都已缓存，源 roll 不再需要。
        if (self.cached_count == self.count) self.releaseRoll();
    } else {
        if (self.scratch) |*old| old.deinit();
        self.scratch = out;
    }
}

fn view(self: *const Self, index: usize, out: *const Image.Out) FrameView {
    return .{
        .index = index,
        .pixels = @ptrCast(out.data_ptr),
        .len = out.data_size,
        .size = .{ .w = @intCast(self.width), .h = @intCast(self.page_height) },
    };
}

/// 在累计 PTS 中定位所在帧：第一个结束时间大于 `position` 的帧。
fn ptsIndex(pts: []const u64, position: u64) usize {
    var lo: usize = 0;
    var hi: usize = pts.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (pts[mid] > position) hi = mid else lo = mid + 1;
    }
    // position 落在最后一帧内部时，lo 正好等于 len
    return if (lo < pts.len) lo else pts.len - 1;
}
