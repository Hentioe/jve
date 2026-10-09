const std = @import("std");
const sdl = @import("sdl");
const Allocator = std.mem.Allocator;
const Preview = @import("display/Preview.zig");
const Gpu = @import("display/Gpu.zig");

pub const State = @import("display/State.zig");
pub const Mode = @import("display/enums.zig").Mode;
pub const Welcome = @import("display/Welcome.zig");
pub const Error = @import("display/errors.zig").Error;
const ExitAction = @import("display/enums.zig").ExitAction;

// 初始化外部状态，从初始模式开始，并响应退出/切换动作
pub fn show(mode: Mode, allocator: Allocator) Error!void {
    var state = try State.init(allocator);
    defer state.deinit();

    var current = mode;
    while (true) {
        const action = try showMode(current, allocator, &state);
        current = switch (action) {
            // 退出
            .quit => return,
            // 切换到另一个模式
            .toggle => switch (current) {
                .pewview => .gpu,
                .gpu => .pewview,
            },
        };
    }
}

// 展示指定模式。窗口、渲染器等资源按需惰性创建，并在模式切换间复用。
fn showMode(mode: Mode, allocator: Allocator, state: *State) Error!ExitAction {
    switch (mode) {
        .pewview => {
            if (state.preview == null)
                state.preview = try Preview.init(allocator, state);
            return try state.preview.?.show();
        },
        .gpu => {
            if (state.gpu == null)
                state.gpu = try Gpu.init(allocator, state);
            return try state.gpu.?.show();
        },
    }
}

pub fn init() Error!void {
    // 设置提示
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_DRIVER, "x11")); // todo: 配置化驱动
    // 强制 1:1 像素映射
    try sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "1"));
    // 初始化 SDL
    try sdl.check(sdl.c.SDL_Init(sdl.c.SDL_INIT_VIDEO));
    // 设置应用元数据
    sdl.check(sdl.c.SDL_SetAppMetadata("JVE", "0.0.0", "jve")) catch {
        std.log.warn("Failed to set app metadata", .{});
    };
    // 设置应用 ID
    sdl.check(sdl.c.SDL_SetHint(sdl.c.SDL_HINT_APP_ID, "jve")) catch {
        std.log.warn("Failed to set app ID", .{});
    };
    // 初始化 ShaderCross
    // todo: 让后端自己去初始化
    try sdl.check(sdl.c.SDL_ShaderCross_Init());
}

pub fn deinit() void {
    sdl.c.SDL_Quit();
}
