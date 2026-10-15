const std = @import("std");
const sdl = @import("sdl");
const ass = @import("ass");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Size2D = shared.Size2D;
const AssRendered = @import("AssRendered.zig");
const text_renderer = @import("text_renderer.zig");
const BuildOptions = text_renderer.Options;
const Uploader = @import("../display/Uploader.zig");
const TextPipeline = @import("TextPipeline.zig");
const TextDrawer = @import("TextDrawer.zig");
const LayoutOptions = @import("options.zig").LayoutOptions;
const Position = @import("shared").Point(f32);
const Widget = @import("Widget.zig");
const Event = @import("Event.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

/// 截断时插入的省略号（U+2026）。
const ELLIPSIS = "…";

allocator: Allocator,
value: []const u8,
raster: AssRendered,
options: LayoutOptions = .{},
drawer: TextDrawer = undefined,
is_drawable: bool = false,

pub fn init(allocator: Allocator, renderer: *const ass.Renderer, value: []const u8, options: BuildOptions) Error!Self {
    var raster = try text_renderer.render(allocator, renderer, value, options);
    errdefer raster.deinit();

    // 超出最大宽度时，截断为「头…尾」（收尾可见、省略中间）后重新栅格化。
    if (options.max_width) |max_width| {
        if (@as(f32, @floatFromInt(raster.width)) > max_width) {
            const fitted = try fitWidth(allocator, renderer, value, options, max_width);
            defer allocator.free(fitted);
            const fitted_raster = try text_renderer.render(allocator, renderer, fitted, options);
            raster.deinit();
            raster = fitted_raster;
        }
    }

    return Self{
        .allocator = allocator,
        .value = value,
        .raster = raster,
    };
}

/// 在 `max_width` 内求最长可显示的「头…尾」字符串（自有内存，调用方释放）。
fn fitWidth(
    allocator: Allocator,
    renderer: *const ass.Renderer,
    value: []const u8,
    options: BuildOptions,
    max_width: f32,
) Error![]u8 {
    // 按 Unicode 码点记录每个码点的起始字节，便于安全切割多字节字符。
    const count = std.unicode.utf8CountCodepoints(value) catch value.len;
    const bounds = try allocator.alloc(usize, count + 1);
    defer allocator.free(bounds);
    {
        var byte: usize = 0;
        var i: usize = 0;
        while (i < count) : (i += 1) {
            bounds[i] = byte;
            byte += @as(usize, std.unicode.utf8ByteSequenceLength(value[byte]) catch 1);
        }
        bounds[count] = value.len;
    }

    const buffer = try allocator.alloc(u8, value.len + ELLIPSIS.len);
    defer allocator.free(buffer);

    // 保留 `k` 个码点：头部 ⌈k/2⌉、尾部 ⌊k/2⌋，中间用省略号。
    const candidate = struct {
        fn build(buf: []u8, src: []const u8, offsets: []const usize, total: usize, k: usize) []const u8 {
            const head = (k + 1) / 2;
            const tail = k - head;
            const head_end = offsets[head];
            const tail_start = offsets[total - tail];
            var len: usize = 0;
            @memcpy(buf[len..][0..head_end], src[0..head_end]);
            len += head_end;
            @memcpy(buf[len..][0..ELLIPSIS.len], ELLIPSIS);
            len += ELLIPSIS.len;
            const tail_len = src.len - tail_start;
            @memcpy(buf[len..][0..tail_len], src[tail_start..]);
            len += tail_len;
            return buf[0..len];
        }
    };

    var best: usize = 0;
    var low: usize = 0;
    var high: usize = count;
    while (low <= high) {
        const mid = low + (high - low) / 2;
        var probe = try text_renderer.render(allocator, renderer, candidate.build(buffer, value, bounds, count, mid), options);
        const width: f32 = @floatFromInt(probe.width);
        probe.deinit();
        if (width <= max_width) {
            best = mid;
            low = mid + 1;
        } else {
            if (mid == 0) break;
            high = mid - 1;
        }
    }

    return allocator.dupe(u8, candidate.build(buffer, value, bounds, count, best));
}

pub fn deinit(self: *Self) void {
    if (self.is_drawable) self.drawer.deinit();
    self.raster.deinit();
    self.* = undefined;
}

pub fn position(self: *Self, value: Position) *Self {
    self.options.position = value;
    return self;
}

pub fn debug(self: *Self, value: bool) void {
    self.options.debug = value;
}

pub fn toWidget(self: *Self, uploader: *Uploader, frame_size: Size2D(i32), pipeline: *TextPipeline) Error!Widget {
    std.debug.assert(!self.is_drawable);
    self.drawer = try TextDrawer.init(self.allocator, uploader, pipeline, frame_size, &self.raster, self.options);
    self.is_drawable = true;

    return .{
        .ptr = @ptrCast(self),
        .vtable = Widget.VTable.of(Self),
    };
}

pub fn draw(self: *Self, cmd: *sdl.GPUCommandBuffer, pass: *sdl.GPURenderPass) void {
    self.drawer.draw(cmd, pass);
}

pub fn event(_: *Self, _: *const Event) void {
    // todo: 增加 hover 事件
}
