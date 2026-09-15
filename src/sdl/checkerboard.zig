const std = @import("std");
const c = @import("c.zig").c;
const helper = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Window = @import("window.zig");
const Self = @This();

const tile_size = 12;
const parten_size = tile_size * 2;

renderer: *c.SDL_Renderer,
texture: *c.SDL_Texture,

pub fn init(renderer: *c.SDL_Renderer) Error!Self {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    // 分配像素数据内存
    const checker_pixels = try allocator.alloc(u8, @intCast(parten_size * parten_size * 4));
    defer allocator.free(checker_pixels);
    // 构造棋盘格像素数据
    var y: usize = 0;
    while (y < parten_size) : (y += 1) {
        var x: usize = 0;
        while (x < parten_size) : (x += 1) {
            const offset = (y * parten_size + x) * 4;
            const is_white = ((x / tile_size) % 2) == ((y / tile_size) % 2);
            const color: u8 = if (is_white) 144 else 100;
            checker_pixels[offset + 0] = color;
            checker_pixels[offset + 1] = color;
            checker_pixels[offset + 2] = color;
            checker_pixels[offset + 3] = 255;
        }
    }
    // 上传棋盘格纹理
    const checker_texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGBA32,
        c.SDL_TEXTUREACCESS_STATIC,
        parten_size,
        parten_size,
    );
    if (!c.SDL_UpdateTexture(
        checker_texture,
        null,
        checker_pixels.ptr,
        parten_size * 4,
    )) {
        helper.printSdlError();
        return Error.SdlUpdateTextureFailed;
    }

    return Self{
        .renderer = renderer,
        .texture = checker_texture,
    };
}

pub fn render(self: Self) void {
    _ = c.SDL_RenderTextureTiled(self.renderer, self.texture, null, 1.0, null);
}

pub fn deinit(self: Self) void {
    c.SDL_DestroyTexture(self.texture);
}
