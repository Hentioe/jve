const std = @import("std");
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const GalleryError = @import("../gallery.zig").Error;
const AiError = @import("ai").Error;

pub const SdlError = error{SdlFailed};
pub const CustomError = error{
    NotDownloaded,
    NoPixelData,
    CreateScreenshotDirFailed, // 创建截图目录失败
};

pub const Error = SdlError || CustomError || SizeError || OrtError || GalleryError || AiError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError;
