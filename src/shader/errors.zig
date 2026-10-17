const std = @import("std");
const SlangError = @import("slang").Error;
const SdlError = @import("sdl").Error;
const ScannerError = @import("../Scanner.zig").Error;

const CustomError = error{
    ShaderReadFailed, // 着色器文件读取失败
};

pub const Error = CustomError || SlangError || SdlError || ScannerError ||
    std.mem.Allocator.Error || std.posix.AccessError;
