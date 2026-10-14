const std = @import("std");
const sdl = @import("sdl");
const config = @import("config");
const errors = @import("errors.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Scanner = @import("../Scanner.zig");
const shader_loader = @import("shader_loader.zig");
const Device = @import("Device.zig");
const Error = errors.Error;
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
        // 如果着色器文件名和背景着色器文件名相同，则不添加进列表，
        // 否则作为后处理管线的一部分
        if (config.get().shaders.background) |background| if (std.mem.eql(u8, file, background)) {
            std.log.info("Found background shader: {s}", .{file});
            // 注意：背景着色器不需要采样器
            const sharder = try shader_loader.loadSlangFile(allocator, gpu, full_path, "main", .fragment, .{ .samplers = 0, .buffers = 0 });
            Device.setBackgroundShader(sharder);
        } else {
            const sharder = try shader_loader.loadSlangFile(allocator, gpu, full_path, "main", .fragment, .{ .samplers = 1, .buffers = 0 });
            try shaders.append(allocator, sharder);
        };
    }
    return shaders;
}
