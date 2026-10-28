const tasks = @import("../tasks.zig");
const RenderDeps = @import("../RenderDeps.zig");
const State = @import("../State.zig");
const Scheduler = tasks.Scheduler;
const Elem = tasks.Elem;
const Error = @import("../../errors.zig").Error;
const Self = @This();

task_sched: *Scheduler,
deps: *RenderDeps,
state: *State,

pub fn pollHandle(self: *Self) Error!void {
    for (try self.task_sched.poll()) |elem| try self.handleOne(elem);
}

fn handleOne(self: *Self, t: Elem) Error!void {
    switch (t.result) {
        .cstr => |cstr| {
            if (t.name == .save_screenshot)
                try self.state.showSuccess(self.deps, "截图已保存：{f}", .{cstr});
        },
        .ok => {
            if (t.name == .copy_screenshot)
                try self.state.showSuccess(self.deps, "已复制到剪切板", .{});
        },
        .err => |err| {
            try self.state.showError(self.deps, "{s}", .{@errorName(err)});
        },
    }

    switch (t.name) {
        .copy_screenshot, .save_screenshot => self.state.screenshot = .default, // 重置截图状态
    }
}
