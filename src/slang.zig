const std = @import("std");
const c = @import("slang_c");
const shared = @import("shared");
const CString = shared.CString;
const Compiler = @import("slang/Compiler.zig");

pub const Error = @import("slang/errors.zig").Error;

var initialized: bool = false;
var compiler: Compiler = undefined;

pub fn init(from: []const u8) Error!void {
    if (initialized) return; // 允许多次调用初始化
    std.log.debug("Initializing Slang ({s})", .{from});
    compiler = try Compiler.init();
    initialized = true;
}

pub fn deinit() void {
    std.debug.assert(initialized);
    std.log.debug("Deinitializing Slang", .{});
    compiler.deinit();
    compiler = undefined;
    initialized = false;
    shared.heap.mallocTrim(); // 编译环境相当占用内存，需立即回收
}

pub fn isInitialized() bool {
    return initialized;
}

/// 默认编译目标，着色器缓存以此为编译环境标识之一
pub const DEFAULT_PROFILE = "spirv_1_5";

pub const Options = struct {
    entry: []const u8 = "main",
    profile: []const u8 = DEFAULT_PROFILE,
};

pub const Compiled = struct {
    blob: c.SlangShimBlob,

    pub fn deinit(self: *Compiled) void {
        c.slang_shim_blob_release(&self.blob);
        self.* = undefined;
    }

    pub fn bytes(self: Compiled) []const u8 {
        const p: [*]const u8 = @ptrCast(self.blob.data.?);
        return p[0..self.blob.size];
    }
};

/// `name` 同时作为模块名和诊断信息里显示的文件名。
/// 返回的 Compiled 直接引用 Slang 的内存，用完调用 deinit。
pub fn compileToSpirv(name: []const u8, source: [:0]const u8, options: Options) !Compiled {
    const c_name = try CString.fromName(name);
    const c_entry = try CString.fromShort(options.entry);
    const c_profile = try CString.fromShort(options.profile);

    var code: c.SlangShimBlob = .{ .data = null, .size = 0, .handle = null };
    var diag: [*c]u8 = null;
    defer if (diag != null) c.slang_shim_free(diag);

    const rc = c.slang_shim_compile_spirv(
        compiler.handle,
        c_name.data(),
        source.ptr,
        c_entry.data(),
        c_profile.data(),
        &code,
        &diag,
    );

    if (diag != null) {
        const msg = std.mem.span(diag);
        if (rc != 0) {
            std.log.err("slang ({d}): {s}", .{ rc, msg });
        } else {
            std.log.warn("slang: {s}", .{msg});
        }
    }
    if (rc != 0) return Error.SlangCompileFailed;

    return .{ .blob = code };
}
