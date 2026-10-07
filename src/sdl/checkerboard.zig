// 由于 sdl_renderer 后端取消了窗口模式，此棋盘格实现并未实际使用。

const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const errors = @import("errors.zig");
const Error = errors.Error;
const Self = @This();

const tile_size = 12;
const parten_size = tile_size * 2;

renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,

pub fn init(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer) Error!Self {
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
    const texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        parten_size,
        parten_size,
    );
    // 更新棋盘格纹理
    try h.check(c.SDL_UpdateTexture(texture, null, pixels.ptr, parten_size * 4));

    return Self{ .renderer = renderer, .texture = texture };
}

pub fn deinit(self: Self) void {
    c.SDL_DestroyTexture(self.texture);
}

pub fn render(self: Self) errors.SdlError!void {
    try h.check(c.SDL_RenderTextureTiled(self.renderer, self.texture, null, 1.0, null));
}
