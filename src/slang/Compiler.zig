const c = @import("slang_c");
const Error = @import("errors.zig").Error;
const Self = @This();

handle: *c.SlangShimCompiler,

pub fn init() Error!Self {
    return .{
        .handle = c.slang_shim_compiler_create() orelse return Error.SlangInitFailed,
    };
}

pub fn deinit(self: *Self) void {
    c.slang_shim_compiler_destroy(self.handle);
    self.* = undefined;
}
