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
    text_banner: *ui.TextBanner,
    state: *State = undefined,

    initial_banner_color: ui.Color,

    const Self = @This();

    pub fn init(deps: *RenderDeps, text_banner: *ui.TextBanner) Self {
        return Self{
            .deps = deps,
            .text_banner = text_banner,
            .initial_banner_color = deps.banner.options.color,
        };
    }

    /// 绑定事件
    pub fn bindEvents(self: *Self, state: *State) void {
        self.state = state;
        self.text_banner.on_hover = ui.Event.Callback(bool).bind(self, Self.bannerHover);
        self.text_banner.on_click = ui.Event.Callback(void).bind(self, Self.bannerClick);
    }

    pub fn bannerHover(self: *Self, is_hover: bool) void {
        std.log.debug("Banner hover state changed: {any}", .{is_hover});
        self.deps.window.is_draggable = !is_hover; // 当鼠标悬停在横幅上时，窗口不可拖动（避免丢失点击事件）
    }

    pub fn bannerClick(_: *Self, _: void) void {
        std.log.debug("Banner clicked", .{});
    }
};
