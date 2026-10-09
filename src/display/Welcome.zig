const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const Size2D = @import("shared").Size2D;
const Window = @import("window.zig");
const RenderDeps = @import("welcome/RenderDeps.zig");
const loop = @import("welcome/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Self = @This();

const WINDOW_SIZE = Size2D(i32){ .w = 1024, .h = 768 };
const WINDOW_OPTIONS = Window.Options{ .windowed = true, .mode = .gpu };

allocator: Allocator,
window: *Window,
gpu: sdl.Gpu,

pub fn init(allocator: Allocator) Error!Self {
    // 初始化「欢迎」模式
    std.log.info("Initializing welcome mode", .{});
    // 创建窗口
    const window = try Window.create(allocator, WINDOW_SIZE, WINDOW_OPTIONS);
    errdefer window.destroy();
    // 创建 GPU
    var gpu = try sdl.Gpu.create();
    errdefer gpu.destroy();
    // 绑定窗口到 GPU 设备
    try gpu.claimWindow(window.sdl_window);

    return Self{ .allocator = allocator, .window = window, .gpu = gpu };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing welcome mode", .{});
    self.gpu.destroy();
    self.window.destroy();
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    var render_deps = try RenderDeps.init(self.allocator, self.window, &self.gpu);
    errdefer render_deps.deinit();

    try self.window.show();
    try loop.run(&render_deps);

    return .quit;
}
