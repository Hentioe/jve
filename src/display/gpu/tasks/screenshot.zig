const std = @import("std");
const sdl = @import("sdl");
const tasks = @import("../tasks.zig");
const Allocator = std.mem.Allocator;
const Screenshot = @import("../../../Screenshot.zig");
const vips = @import("vips");
const LImage = vips.LImage;

pub const args = std.meta.ArgsTuple(@TypeOf(launch));

pub fn launch(
    sched: *tasks.Scheduler,
    name: tasks.Name,
    allocator: Allocator,
    gpu_dvice: *const sdl.Gpu,
    tex: *sdl.GPUTexture,
    image: *LImage,
) tasks.Result {
    var s = Screenshot.init(allocator, gpu_dvice, tex, image) catch |err| {
        return sched.buildDone(name, .{ .err = err });
    };
    defer s.deinit();

    switch (name) {
        .save_screenshot => if (s.saveToFile()) |saved| {
            return sched.buildDone(name, .{ .cstr = saved.filepath });
        } else |err| {
            return sched.buildDone(name, .{ .err = err });
        },
        .copy_screenshot => if (s.copyToClipboard()) {
            return sched.buildDone(name, .{ .ok = {} });
        } else |err| {
            return sched.buildDone(name, .{ .err = err });
        },
    }
}
