const std = @import("std");
const ass = @import("ass");
const consts = @import("consts.zig");
const AssLibrary = @import("AssLibrary.zig");
const Error = @import("errors.zig").Error;

// 图标绘制坐标空间（PlayRes），图标路径按此空间（0..PLAY_RES）书写。
pub const PLAY_RES = 320;
// scale = 1 时输出图标的边长（像素）。frame 尺寸据此结合 scale 计算。
pub const BASE_SIZE: u32 = 32;

var initialized: bool = false;
var instance: ass.Renderer = undefined;

pub fn get() *const ass.Renderer {
    return &instance;
}

pub fn init() Error!void {
    std.debug.assert(!initialized);
    instance = try ass.Renderer.init(try AssLibrary.get());
    instance.setFonts(null, consts.DEFAULT_FONT, ass.c.ASS_FONTPROVIDER_AUTODETECT, null, 1);
    initialized = true;
}

pub fn deinit() void {
    std.debug.assert(initialized);
    instance.deinit("icon renderer");
    instance = undefined;
    initialized = false;
}
