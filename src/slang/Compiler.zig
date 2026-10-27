const c = @import("slang_c");
const SlangError = @import("errors.zig").SlangError;
const Self = @This();

handle: *c.SlangShimCompiler,

pub fn init() SlangError!Self {
    return .{
        .handle = c.slang_shim_compiler_create() orelse return SlangError.SlangInitFailed,
    };
}

pub fn deinit(self: *Self) void {
    c.slang_shim_compiler_destroy(self.handle);
    self.* = undefined;
}
