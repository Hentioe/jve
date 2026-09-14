const std = @import("std");
const imgLoader = @import("image_loader.zig");

pub const SdlRenderer = @import("sdl/renderer.zig");
pub const loadImage = imgLoader.loadImage;
pub const loadedImage = imgLoader.Loaded;
pub const LoaderError = imgLoader.Error;
