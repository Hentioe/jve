const std = @import("std");
const shared = @import("shared");
const tasks = @import("../tasks.zig");
const ai = @import("../../../ai.zig");
const extractor = @import("../../../extractor.zig");
const Image = @import("vips").Image;
const Allocator = std.mem.Allocator;
const Point = shared.Point(f32);
const Model = ai.OrtRunnable.Model;

/// 模型输出的遮罩数据。任务负责生成，PollHandler 负责释放。
pub const Mask = struct {
    width: u32,
    height: u32,
    out: Image.Out,

    pub fn deinit(self: *Mask) void {
        self.out.deinit();
        self.* = undefined;
    }
};

pub const args = std.meta.ArgsTuple(@TypeOf(launch));

pub fn launch(
    sched: *tasks.Scheduler,
    name: tasks.Name,
    allocator: Allocator,
    extracted: extractor.Extracted,
    click: ?Point,
) tasks.Result {
    // 输入像素由循环线程提取并移交，任务结束后释放
    var input_data = extracted;
    defer input_data.deinit();

    const mask = run(allocator, input_data, click) catch |err| {
        return sched.buildDone(name, .{ .err = err });
    };
    return sched.buildDone(name, .{ .mask = mask });
}

fn run(allocator: Allocator, extracted: extractor.Extracted, click: ?Point) !Mask {
    // 有点击座标时使用 MagicTouch，否则使用 BiRefNet
    const model: Model = if (click != null) .magic_touch else .birefnet;
    const model_input: ai.Input = .{
        .data_ptr = extracted.data.ptr,
        .shape = extracted.shape,
        .click_position = click,
    };

    try ai.remover.init(allocator);
    var image = try ai.remover.remove(model, model_input);
    defer image.deinit();

    const out = try image.allocOutInMemory();
    return .{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .out = out,
    };
}
