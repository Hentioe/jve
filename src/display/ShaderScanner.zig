const std = @import("std");
const sdl = @import("sdl");
const errors = @import("errors.zig");
const shader_loader = @import("shader_loader.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Error = errors.Error;
const Scanner = @import("../Scanner.zig");
const Self = @This();

allocator: Allocator,
scanner: Scanner,

pub fn init(allocator: Allocator, sharder_dir: []const u8) Error!Self {
    const scanner = try Scanner.init(allocator, sharder_dir, &[_][]const u8{".slang"}, .{});

    return Self{ .allocator = allocator, .scanner = scanner };
}

pub fn deinit(self: *Self) void {
    self.scanner.deinit();
    self.* = undefined;
}

pub fn scan(self: *Self) Error!void {
    try self.scanner.scan();
}

pub fn compileShaders(self: *Self, allocator: Allocator, gpu: *const sdl.Gpu) Error!ArrayList(*sdl.c.SDL_GPUShader) {
    const base_dir = self.scanner.dir_path;
    const files = self.scanner.items();
    var shaders = try ArrayList(*sdl.c.SDL_GPUShader).initCapacity(allocator, 0);
    for (files) |file| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, file });
        defer allocator.free(full_path);
        const sharder = try shader_loader.loadSlangFile(allocator, gpu, full_path, "main", .fragment, .{ .samplers = 1, .buffers = 0 });
        try shaders.append(allocator, sharder);
    }
    return shaders;
}
