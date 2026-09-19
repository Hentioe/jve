// 渲染后端
pub const Backend = enum {
    SdlRenderer,
    SdlGpu,
};

// 渲染退出
pub const RenderExit = enum {
    Quit,
    Toggle,
};
