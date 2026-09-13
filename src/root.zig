const std = @import("std");
const imgLoader = @import("image_loader.zig");
const sdlRenderer = @import("sdl_renderer.zig");

pub const loadImage = imgLoader.loadImage;
pub const loadedImage = imgLoader.Loaded;
pub const LoaderError = imgLoader.Error;
pub const renderImage = sdlRenderer.render;
pub const SdlRendererError = sdlRenderer.Error;
