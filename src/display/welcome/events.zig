const std = @import("std");
const sdl = @import("sdl");
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const State = @import("State.zig");
const RenderDeps = @import("RenderDeps.zig");
const ui = @import("../../ui.zig");
const Error = @import("../errors.zig").Error;

pub fn handle(event: *sdl.Event, state: *State) void {
    if (event.type == sdl.EVENT_QUIT) state.running = false;
}

pub const Context = struct {
    io: std.Io,
    allocator: Allocator,
    deps: *RenderDeps,
    state: *State = undefined,
    pointer_cursor: *sdl.Cursor,
    default_cursor: *sdl.Cursor,

    initial_banner_color: ui.Color,

    const Self = @This();

    pub fn init(io: std.Io, allocator: Allocator, deps: *RenderDeps) Error!Self {
        return Self{
            .io = io,
            .allocator = allocator,
            .deps = deps,
            .initial_banner_color = deps.banner.options.color,
            .pointer_cursor = try sdl.createSystemCursor(sdl.SYSTEM_CURSOR_POINTER),
            .default_cursor = try sdl.createSystemCursor(sdl.SYSTEM_CURSOR_DEFAULT),
        };
    }

    pub fn deinit(self: *Self) void {
        sdl.destroyCursor(self.pointer_cursor);
        sdl.destroyCursor(self.default_cursor);
    }

    /// 绑定事件
    pub fn bindEvents(self: *Self, state: *State) void {
        self.state = state;
        self.deps.banner.on_hover = ui.Event.Callback(bool).bind(self, Self.bannerHover);
        self.deps.banner.on_click = ui.Event.Callback(void).bind(self, Self.bannerClick);
    }

    pub fn bannerHover(self: *Self, is_hover: bool) void {
        std.log.debug("Banner hover state changed: {any}", .{is_hover});
        self.deps.window.is_draggable = !is_hover; // 当鼠标悬停在横幅上时，窗口不可拖动（避免丢失点击事件）
        const banner = self.deps.banner;
        if (is_hover) {
            banner.setColor(.rgba01(1.0, 1.0, 1.0, 0.15));
            // 切换到手型光标
            sdl.setCursor(self.pointer_cursor) catch |err| std.log.err("Failed to set pointer cursor: {}", .{err});
        } else {
            banner.setColor(self.initial_banner_color);
            sdl.setCursor(self.default_cursor) catch |err| std.log.err("Failed to set default cursor: {}", .{err});
        }
    }

    pub fn bannerClick(self: *Self, _: void) void {
        std.log.debug("Banner clicked", .{});
        shared.opener.open(self.io, "https://github.com/Hentioe/jve") catch |reason| {
            std.log.err("Failed to open URL: {}", .{reason});
            self.deps.banner.setText("打开仓库链接失败了") catch |err| std.log.err("Failed to set banner text: {}", .{err});
            self.deps.banner.setColor(.rgba01(1.0, 0.0, 0.0, 0.5));
        };
    }
};
