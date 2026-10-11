const std = @import("std");
const SdlError = @import("sdl").Error;
const AssError = @import("ass").Error;
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const GalleryError = @import("../gallery.zig").Error;
const AiError = @import("ai").Error;

const CustomError = error{
    AssNotRendered, // 字幕没有渲染
};

pub const Error = CustomError || SdlError || AssError || SizeError || OrtError || GalleryError || AiError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError;
