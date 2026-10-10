const std = @import("std");
const sdl = @import("sdl");
const LImage = @import("vips").LImage;
const Window = @import("../window.zig");
const app_env = @import("../../app_env.zig");
const Error = @import("../errors.zig").Error;
const Self = @This();

window: *Window,
renderer: *sdl.Renderer,
image: LImage,
texture: *sdl.Texture,

pub fn init(window: *Window, renderer: *sdl.Renderer, image: LImage) Error!Self {
    // 创建纹理（先尝试从外部状态缓存中读取模式切换时保留的结果）
    const texture = if (try app_env.writer().readTexture(renderer)) |tex|
        tex
    else
        try createTexture(renderer, &image);

    return Self{
        .window = window,
        .renderer = renderer,
        .image = image,
        .texture = texture,
    };
}

pub fn deinit(self: *Self) void {
    sdl.Renderer.destroyTexture(self.texture);
    self.* = undefined;
}

// 更换当前图片并重建纹理
pub fn setImage(self: *Self, image: LImage) Error!void {
    sdl.Renderer.destroyTexture(self.texture);
    self.image = image;
    self.texture = try createTexture(self.renderer, &image);
}

fn createTexture(renderer: *sdl.Renderer, image: *const LImage) Error!*sdl.Texture {
    // 计算 pitch
    const pitch = image.shape.w * image.shape.c;
    std.log.info("Pitch: {d}", .{pitch});
    // 创建图片纹理
    const texture = try renderer.createTexture(
        sdl.c.SDL_PIXELFORMAT_RGBA32,
        sdl.c.SDL_TEXTUREACCESS_STATIC,
        image.shape.w,
        image.shape.h,
    );
    // 开启纹理混合模式
    try sdl.Renderer.setTextureBlendMode(texture, sdl.c.SDL_BLENDMODE_BLEND);
    // 上传纹理
    try sdl.Renderer.updateTexture(
        texture,
        null,
        image.pixels_ptr,
        pitch,
    );

    return texture;
}
