const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

sdl_renderer: *c.SDL_Renderer,

pub fn create(window: *c.SDL_Window) Error!Self {
    return Self{
        .sdl_renderer = try h.check(c.SDL_CreateRenderer(window, null)),
    };
}

pub fn destroy(self: *Self) void {
    c.SDL_DestroyRenderer(self.sdl_renderer);
    self.sdl_renderer = undefined;
}

pub fn setRenderDrawColor(self: *Self, r: u8, g: u8, b: u8, a: u8) Error!void {
    try h.check(c.SDL_SetRenderDrawColor(self.sdl_renderer, r, g, b, a));
}

pub fn setRenderVSync(self: *Self, vsync: c_int) Error!void {
    try h.check(c.SDL_SetRenderVSync(self.sdl_renderer, vsync));
}

pub fn renderClear(self: *Self) Error!void {
    try h.check(c.SDL_RenderClear(self.sdl_renderer));
}

pub fn renderTextureRotated(
    self: *Self,
    texture: ?*c.SDL_Texture,
    srcrect: ?*const c.SDL_FRect,
    dstrect: ?*const c.SDL_FRect,
    angle: f64,
    center: ?*const c.SDL_FPoint,
    flip: c.SDL_FlipMode,
) Error!void {
    try h.check(c.SDL_RenderTextureRotated(self.sdl_renderer, texture, srcrect, dstrect, angle, center, flip));
}

pub fn renderPresent(self: *Self) Error!void {
    try h.check(c.SDL_RenderPresent(self.sdl_renderer));
}

pub fn renderTextureTiled(
    self: *Self,
    texture: ?*c.SDL_Texture,
    srcrect: ?*const c.SDL_FRect,
    scale: f32,
    dstrect: ?*const c.SDL_FRect,
) Error!void {
    try h.check(c.SDL_RenderTextureTiled(self.sdl_renderer, texture, srcrect, scale, dstrect));
}

pub fn createTexture(
    self: *Self,
    format: c.SDL_PixelFormat,
    access: c.SDL_TextureAccess,
    w: c_int,
    hgt: c_int,
) Error!*c.SDL_Texture {
    const texture = try h.check(c.SDL_CreateTexture(self.sdl_renderer, format, access, w, hgt));
    return texture;
}

pub fn destroyTexture(texture: ?*c.SDL_Texture) void {
    c.SDL_DestroyTexture(texture);
}

pub fn setTextureBlendMode(texture: ?*c.SDL_Texture, mode: c.SDL_BlendMode) Error!void {
    try h.check(c.SDL_SetTextureBlendMode(texture, mode));
}

pub fn updateTexture(
    texture: ?*c.SDL_Texture,
    rect: ?*const c.SDL_Rect,
    pixels: ?*const anyopaque,
    pitch: c_int,
) Error!void {
    try h.check(c.SDL_UpdateTexture(texture, rect, pixels, pitch));
}
