const std = @import("std");
const SdlError = @import("sdl").Error;
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const GalleryError = @import("../gallery.zig").Error;
const AiError = @import("ai").Error;

pub const Error = SdlError || SizeError || OrtError || GalleryError || AiError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError;
