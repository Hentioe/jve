const std = @import("std");
const SdlError = @import("sdl").Error;
const AssError = @import("ass").Error;
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const AiError = @import("ai").Error;
const SlangError = @import("slang").Error;
const GalleryError = @import("../gallery.zig").Error;

const CustomError = error{
    AssNotRendered, // 字幕没有渲染
    ShaderReadFailed, // 着色器文件读取失败
};

pub const Error = CustomError || SdlError || AssError || SizeError || OrtError || GalleryError || AiError || SlangError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError || std.fs.File.OpenError;
