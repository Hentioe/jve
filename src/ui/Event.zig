pub const ClickState = enum { down, up, none };

click: ClickState = .none,
mouse_x: f32,
mouse_y: f32,

pub fn Callback(comptime Arg: type) type {
    return struct {
        const Self = @This();

        ctx: *anyopaque,
        func: *const fn (ctx: *anyopaque, arg: Arg) void,

        /// comptime 生成转换函数，使用者写的是 *Context，不用手动转型
        pub fn bind(ctx: anytype, comptime method: fn (@TypeOf(ctx), Arg) void) Self {
            const Ptr = @TypeOf(ctx);
            const thunk = struct {
                fn f(p: *anyopaque, arg: Arg) void {
                    const self: Ptr = @ptrCast(@alignCast(p));
                    method(self, arg);
                }
            }.f;
            return .{ .ctx = ctx, .func = thunk };
        }

        pub fn call(self: Self, arg: Arg) void {
            self.func(self.ctx, arg);
        }
    };
}
