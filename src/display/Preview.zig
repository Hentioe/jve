const std = @import("std");
const sdl = @import("sdl");
const gallery = @import("../gallery.zig");
const Window = @import("window.zig");
const app_env = @import("../app_env.zig");
const RenderDeps = @import("preview/RenderDeps.zig");
const loop = @import("preview/loop.zig");
const ExitAction = @import("enums.zig").ExitAction;
const Error = @import("errors.zig").Error;
const Self = @This();

window: *Window,
renderer: sdl.Renderer,

pub fn init(allocator: std.mem.Allocator) Error!Self {
    // 初始化「预览」模式
    std.log.info("Initializing preview mode", .{});
    const image = try gallery.current();
    // 创建窗口
    const window = try Window.create(
        allocator,
        image.shape.toSize2D(i32),
        .{ .windowed = false, .mode = .preview },
    );
    errdefer window.destroy();
    // 创建渲染器
    var renderer = try sdl.Renderer.create(window.sdl_window);
    errdefer renderer.destroy();
    // 开启垂直同步
    try renderer.setRenderVSync(1);
    // 记录图片形状
    app_env.writer().image_shape = image.shape;

    return Self{
        .window = window,
        .renderer = renderer,
    };
}

pub fn deinit(self: *Self) void {
    std.log.debug("Deinitializing preview mode", .{});
    self.renderer.destroy();
    self.window.destroy();
    self.* = undefined;
}

pub fn show(self: *Self) Error!ExitAction {
    const image = try gallery.current();
    var deps = try RenderDeps.init(self.window, &self.renderer, image);
    errdefer deps.deinit();

    // 更新窗口标题
    try self.window.setTitle(image.file_name);
    // 显示窗口
    try self.window.show();

    return try loop.run(&deps);
}
