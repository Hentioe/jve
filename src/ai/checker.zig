const std = @import("std");
const config = @import("config");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;

/// 检查模型目录是否存在，存在则返回模型目录完整路径。
pub fn modelDirCheck(allocator: Allocator) Error![]const u8 {
    const model_dir = config.get().models.dir;
    const full_path = try config.allocFullPath(allocator, model_dir);
    const cwd = std.fs.cwd();
    cwd.access(full_path, .{}) catch |err| {
        if (err == std.fs.Dir.AccessError.FileNotFound) {
            return Error.ModelDirNotFound;
        } else {
            std.log.err("Failed to access model directory: {}", .{err});
            return Error.ModelDirAccessError;
        }
    };

    return full_path;
}

/// 检查模型文件是否存在，存在则返回模型文件完整路径。
pub fn modelFileCheck(allocator: Allocator, model_dir: []const u8, model_file: []const u8) Error![]const u8 {
    // 检查模型文件是否存在
    const full_path = try std.fs.path.join(allocator, &.{ model_dir, model_file });
    const cwd = std.fs.cwd();
    cwd.access(full_path, .{}) catch |err| {
        if (err == std.fs.Dir.AccessError.FileNotFound) {
            return Error.ModelFileNotFound;
        } else {
            std.log.err("Failed to access model file: {}", .{err});
            return Error.ModelFileAccessError;
        }
    };

    return full_path;
}
