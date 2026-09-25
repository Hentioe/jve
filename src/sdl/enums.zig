// 渲染后端
pub const Backend = enum {
    sdl_renderer,
    sdl_gpu,
};

pub const RenderNext = enum {
    quit,
    toggle,
};
