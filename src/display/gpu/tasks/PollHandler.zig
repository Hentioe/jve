const shared = @import("shared");
const tasks = @import("../tasks.zig");
const RenderDeps = @import("../RenderDeps.zig");
const State = @import("../State.zig");
const Device = @import("../../../Device.zig");
const Scheduler = tasks.Scheduler;
const Elem = tasks.Elem;
const Error = @import("../../errors.zig").Error;
const Size2D = shared.Size2D;
const Self = @This();

task_sched: *Scheduler,
deps: *RenderDeps,
state: *State,

pub fn pollHandle(self: *Self) Error!void {
    for (try self.task_sched.poll()) |*elem| try self.handleOne(elem);
}

fn handleOne(self: *Self, t: *Elem) Error!void {
    // 结果可能持有的数据（如遮罩）统一由 Result 释放
    defer t.result.deinit();

    switch (t.result) {
        .cstr => |cstr| {
            if (t.name == .save_screenshot)
                try self.state.showSuccess(self.deps, "截图已保存：{f}", .{cstr});
        },
        .ok => {
            if (t.name == .copy_screenshot)
                try self.state.showSuccess(self.deps, "已复制到剪切板", .{});
        },
        .mask => |mask| {
            const size: Size2D(u32) = .{ .w = mask.width, .h = mask.height };
            const uploader = try Device.getUploader();
            const new_mask = try uploader.uploadTextureBorrowed(&self.deps.offscreen_info, mask.out.data_ptr, size);
            try uploader.submit();

            if (self.state.tex_mask) |tex| self.deps.device.releaseGPUTexture(tex); // 释放旧遮罩纹理
            self.state.tex_mask = new_mask;
        },
        .err => |err| {
            try self.state.showError(self.deps, "任务出错：{s}", .{@errorName(err)});
        },
    }

    switch (t.name) {
        .copy_screenshot, .save_screenshot => self.state.screenshot = .default, // 重置截图状态
        .remove_bg => self.state.is_busy = false, // 任务结束，退出繁忙状态
    }
}
