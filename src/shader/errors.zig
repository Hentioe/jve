const std = @import("std");
const SlangError = @import("slang").Error;
const SdlError = @import("sdl").Error;
const ConfigError = @import("config").Error;
const ScannerError = @import("../Scanner.zig").Error;

const CustomError = error{
    ShaderReadFailed, // 着色器文件读取失败
    CacheDirFailed, // 缓存目录创建失败
    CacheReadFailed, // 缓存文件读取失败
    CacheParseFailed, // 缓存摘要解析失败
    CacheWriteFailed, // 缓存文件写入失败
};

pub const Error = CustomError || SlangError || SdlError || ConfigError || ScannerError ||
    std.mem.Allocator.Error || std.posix.AccessError;
