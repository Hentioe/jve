// 由于 sdl_renderer 后端取消了窗口模式，此棋盘格实现并未实际使用。

const std = @import("std");
const c = @import("sdl").c;
const errors = @import("errors.zig");
const Error = errors.Error;
const Renderer = @import("sdl").Renderer;
const Self = @This();

const tile_size = 12;
const parten_size = tile_size * 2;

renderer: Renderer,
texture: *c.SDL_Texture,

pub fn init(allocator: std.mem.Allocator, renderer: Renderer) Error!Self {
    // 分配像素数据内存
    const pixels = try allocator.alloc(u8, @intCast(parten_size * parten_size * 4));
    defer allocator.free(pixels);
    // 构造棋盘格像素数据
    var y: usize = 0;
    while (y < parten_size) : (y += 1) {
        var x: usize = 0;
        while (x < parten_size) : (x += 1) {
            const offset = (y * parten_size + x) * 4;
            const is_white = ((x / tile_size) % 2) == ((y / tile_size) % 2);
            const color: u8 = if (is_white) 144 else 100;
            pixels[offset + 0] = color;
            pixels[offset + 1] = color;
            pixels[offset + 2] = color;
            pixels[offset + 3] = 255;
        }
    }
    // 上传棋盘格纹理
    var self = Self{ .renderer = renderer, .texture = undefined };
    self.texture = try self.renderer.createTexture(
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        parten_size,
        parten_size,
    );
    // 更新棋盘格纹理
    try Renderer.updateTexture(self.texture, null, pixels.ptr, parten_size * 4);

    return self;
}

pub fn deinit(self: Self) void {
    Renderer.destroyTexture(self.texture);
}

pub fn render(self: *Self) errors.SdlError!void {
    try self.renderer.renderTextureTiled(self.texture, null, 1.0, null);
}
