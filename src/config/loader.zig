const std = @import("std");
const toml = @import("toml");
const app_env = @import("../app_env.zig");
const paths = @import("paths.zig");
const Allocator = std.mem.Allocator;
const Unresolved = @import("Unresolved.zig");
const Error = @import("errors.zig").Error;

pub const Loaded = struct {
    parsed: ?toml.Parsed(Unresolved) = null,

    pub fn deinit(self: *Loaded) void {
        if (self.parsed) |p| p.deinit();
    }

    pub fn config(self: *const Loaded) ?Unresolved {
        if (self.parsed) |p| return p.value;
        return null;
    }
};

/// 加载配置文件返回 `Loaded` 实例，释放需调用 `deinit` 方法。
pub fn load(allocator: Allocator, config_path: ?[]const u8) Error!Loaded {
    const path_from_external = config_path != null;
    var path: ?[]const u8 = undefined;
    if (config_path) |p| {
        path = p;
    } else {
        path = try paths.findConfigFile(allocator, "jve", "config.toml");
    }

    defer if (path) |p| if (!path_from_external) allocator.free(p);

    // 如果存在配置文件，解析它。否则返回默认配置。
    if (path) |p| {
        std.log.info("Loading config file: {s}", .{p});

        var parser = toml.Parser(Unresolved).init(allocator);
        defer parser.deinit();

        const parsed = parser.parseFile(p) catch |err| {
            return app_env.report(Error.ConfigParseFailed, @src(), "配置解析失败：{s}", .{@errorName(err)});
        };

        return .{ .parsed = parsed };
    }

    return .{};
}
