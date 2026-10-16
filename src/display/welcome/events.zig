const std = @import("std");
const sdl = @import("sdl");
const State = @import("State.zig");
const RenderDeps = @import("RenderDeps.zig");
const ui = @import("../../ui.zig");

pub fn handle(event: *sdl.Event, state: *State) void {
    if (event.type == sdl.EVENT_QUIT) state.running = false;
}

pub const Context = struct {
    deps: *RenderDeps,
    title_bar: *ui.TitleBar,
    state: *State = undefined,

    initial_banner_color: ui.Color,

    const Self = @This();

    pub fn init(deps: *RenderDeps, title_bar: *ui.TitleBar) Self {
        return Self{
            .deps = deps,
            .title_bar = title_bar,
            .initial_banner_color = deps.banner.options.color,
        };
    }

    /// 绑定事件
    pub fn bindEvents(self: *Self, state: *State) void {
        self.state = state;
        self.title_bar.on_close = ui.Event.Callback(void).bind(self, Self.close);
        self.title_bar.on_minimize = ui.Event.Callback(void).bind(self, Self.minimize);
        self.title_bar.on_button_hover = ui.Event.Callback(bool).bind(self, Self.titleBarButtonHover);
        self.deps.banner.on_hover = ui.Event.Callback(bool).bind(self, Self.bannerHover);
        self.deps.banner.on_click = ui.Event.Callback(void).bind(self, Self.bannerClick);
    }

    pub fn bannerHover(self: *Self, is_hover: bool) void {
        std.log.debug("Banner hover state changed: {any}", .{is_hover});
        self.deps.window.is_draggable = !is_hover; // 当鼠标悬停在横幅上时，窗口不可拖动（避免丢失点击事件）
        const banner = self.deps.banner;
        if (is_hover) {
            banner.setColor(.rgba(1.0, 1.0, 1.0, 0.15));
        } else {
            banner.setColor(self.initial_banner_color);
        }
    }

    pub fn bannerClick(_: *Self, _: void) void {
        std.log.debug("Banner clicked", .{});
    }

    pub fn titleBarButtonHover(self: *Self, is_hover: bool) void {
        std.log.debug("Title bar button hover state changed: {any}", .{is_hover});
        self.deps.window.is_draggable = !is_hover; // 当鼠标悬停在标题栏按钮上时，窗口不可拖动（避免丢失点击事件）
    }

    pub fn close(self: *Self, _: void) void {
        std.log.debug("Close button clicked", .{});
        self.state.running = false;
    }

    pub fn minimize(self: *Self, _: void) void {
        std.log.debug("Minimize button clicked", .{});
        self.deps.window.minimize() catch |err| std.log.err("Failed to minimize window: {any}", .{err});
    }
};
