const sdl = @import("sdl");
const Self = @This();

pub const ClickState = enum { down, up, none };

click: ClickState = .none,
mouse_x: f32,
mouse_y: f32,

pub fn fromSdl(event: *const sdl.Event) ?Self {
    return switch (event.type) {
        sdl.c.SDL_EVENT_MOUSE_MOTION => .{
            .mouse_x = event.motion.x,
            .mouse_y = event.motion.y,
        },
        sdl.EVENT_MOUSE_BUTTON_DOWN, sdl.EVENT_MOUSE_BUTTON_UP => .{
            .click = if (event.type == sdl.EVENT_MOUSE_BUTTON_DOWN) .down else .up,
            .mouse_x = event.button.x,
            .mouse_y = event.button.y,
        },
        else => null,
    };
}

pub fn Callback(comptime Arg: type) type {
    return struct {
        const Caller = @This();

        ctx: *anyopaque,
        func: *const fn (ctx: *anyopaque, arg: Arg) void,

        /// comptime 生成转换函数，使用者写的是 *Context，不用手动转型
        pub fn bind(ctx: anytype, comptime method: fn (@TypeOf(ctx), Arg) void) Caller {
            const Ptr = @TypeOf(ctx);
            const thunk = struct {
                fn f(p: *anyopaque, arg: Arg) void {
                    const self: Ptr = @ptrCast(@alignCast(p));
                    method(self, arg);
                }
            }.f;
            return .{ .ctx = ctx, .func = thunk };
        }

        pub fn call(caller: Caller, arg: Arg) void {
            caller.func(caller.ctx, arg);
        }
    };
}
