const std = @import("std");
const errors = @import("sdl/errors.zig");

pub const c = @import("sdl_c");
pub const h = @import("sdl/helper.zig");
pub const Gpu = @import("sdl/Gpu.zig");
pub const Renderer = @import("sdl/Renderer.zig");
pub const check = h.check;
pub const Error = errors.Error;

pub fn acquireGPUSwapchainTexture(cmd_buf: *GPUCommandBuffer, window: *Window, swapchain_texture: *?*GPUTexture, width: ?*u32, height: ?*u32) Error!void {
    try h.check(c.SDL_AcquireGPUSwapchainTexture(cmd_buf, window, swapchain_texture, width, height));
}

pub fn waitAndAcquireGPUSwapchainTexture(cmd_buf: *GPUCommandBuffer, window: *Window, swapchain_texture: *?*GPUTexture, width: ?*u32, height: ?*u32) Error!void {
    try h.check(c.SDL_WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, swapchain_texture, width, height));
}

pub fn submitGPUCommandBuffer(cmd_buf: *GPUCommandBuffer) Error!void {
    try h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf));
}

pub fn getTicks() u64 {
    return c.SDL_GetTicks();
}

pub fn createSystemCursor(cursor: SystemCursor) Error!*Cursor {
    return h.check(c.SDL_CreateSystemCursor(cursor));
}

pub fn destroyCursor(cursor: *Cursor) void {
    c.SDL_DestroyCursor(cursor);
}

pub fn setCursor(cursor: *Cursor) Error!void {
    return h.check(c.SDL_SetCursor(cursor));
}

pub fn waitEvent(event: *Event) bool {
    return c.SDL_WaitEvent(event);
}

pub fn pollEvent(event: *Event) bool {
    return c.SDL_PollEvent(event);
}

// -- 类型别名 --
// 事件
pub const Event = c.SDL_Event;
pub const EVENT_QUIT = c.SDL_EVENT_QUIT;
pub const EVENT_MOUSE_BUTTON_DOWN = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
pub const EVENT_MOUSE_BUTTON_UP = c.SDL_EVENT_MOUSE_BUTTON_UP;
pub const EVENT_WINDOW_MINIMIZED = c.SDL_EVENT_WINDOW_MINIMIZED;
pub const EVENT_WINDOW_RESTORED = c.SDL_EVENT_WINDOW_RESTORED;
pub const EVENT_KEY_DOWN = c.SDL_EVENT_KEY_DOWN;
pub const EVENT_KEY_UP = c.SDL_EVENT_KEY_UP;
// 提示
pub const HINT_MOUSE_FOCUS_CLICKTHROUGH = c.SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH;
// 窗口
pub const Window = c.SDL_Window;
// SDL_Renderer
pub const Texture = c.SDL_Texture;
// SDL_GPU
pub const GPUCommandBuffer = c.SDL_GPUCommandBuffer;
pub const GPUColorTargetInfo = c.SDL_GPUColorTargetInfo;
pub const GPUColorTargetBlendState = c.SDL_GPUColorTargetBlendState;
pub const GPU_BLENDFACTOR_ONE = c.SDL_GPU_BLENDFACTOR_ONE;
pub const GPU_BLENDFACTOR_SRC_ALPHA = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA;
pub const GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA;
pub const GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA;
pub const GPU_BLENDOP_ADD = c.SDL_GPU_BLENDOP_ADD;
pub const GPU_LOADOP_CLEAR = c.SDL_GPU_LOADOP_CLEAR;
pub const GPU_LOADOP_LOAD = c.SDL_GPU_LOADOP_LOAD;
pub const GPU_STOREOP_STORE = c.SDL_GPU_STOREOP_STORE;
pub const GPURenderPass = c.SDL_GPURenderPass;
pub const GPUGraphicsPipeline = c.SDL_GPUGraphicsPipeline;
pub const GPUGraphicsPipelineCreateInfo = c.SDL_GPUGraphicsPipelineCreateInfo;
pub const GPUGraphicsPipelineTargetInfo = c.SDL_GPUGraphicsPipelineTargetInfo;
pub const GPUShader = c.SDL_GPUShader;
pub const GPUTexture = c.SDL_GPUTexture;
pub const GPUTextureCreateInfo = c.SDL_GPUTextureCreateInfo;
pub const GPUSamplerCreateInfo = c.SDL_GPUSamplerCreateInfo;
pub const GPU_FILTER_LINEAR = c.SDL_GPU_FILTER_LINEAR;
pub const GPU_SAMPLERMIPMAPMODE_LINEAR = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR;
pub const GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE;
pub const GPU_TEXTUREFORMAT_R8G8B8A8_UNORM = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM;
pub const GPU_TEXTUREUSAGE_SAMPLER = c.SDL_GPU_TEXTUREUSAGE_SAMPLER;
pub const GPU_TEXTUREUSAGE_COLOR_TARGET = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET;
pub const GPUBuffer = c.SDL_GPUBuffer;
pub const GPUBufferBinding = c.SDL_GPUBufferBinding;
pub const GPU_VERTEXELEMENTFORMAT_FLOAT2 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2;
pub const GPU_VERTEXELEMENTFORMAT_FLOAT3 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3;
pub const GPUBufferCreateInfo = c.SDL_GPUBufferCreateInfo;
pub const GPUVertexAttribute = c.SDL_GPUVertexAttribute;
pub const GPUVertexInputState = c.SDL_GPUVertexInputState;
pub const GPUVertexBufferDescription = c.SDL_GPUVertexBufferDescription;
pub const GPU_VERTEXINPUTRATE_VERTEX = c.SDL_GPU_VERTEXINPUTRATE_VERTEX;
pub const GPU_BUFFERUSAGE_VERTEX = c.SDL_GPU_BUFFERUSAGE_VERTEX;
// 光标
pub const Cursor = c.SDL_Cursor;
pub const SystemCursor = c.SDL_SystemCursor;
pub const SYSTEM_CURSOR_DEFAULT = c.SDL_SYSTEM_CURSOR_DEFAULT;
pub const SYSTEM_CURSOR_POINTER = c.SDL_SYSTEM_CURSOR_POINTER;

// 按键
pub const Keycode = c.SDL_Keycode;
pub const Key = enum(Keycode) {
    a = c.SDLK_A,
    b = c.SDLK_B,
    c = c.SDLK_C,
    d = c.SDLK_D,
    e = c.SDLK_E,
    f = c.SDLK_F,
    g = c.SDLK_G,
    h = c.SDLK_H,
    i = c.SDLK_I,
    j = c.SDLK_J,
    k = c.SDLK_K,
    l = c.SDLK_L,
    m = c.SDLK_M,
    n = c.SDLK_N,
    o = c.SDLK_O,
    p = c.SDLK_P,
    q = c.SDLK_Q,
    r = c.SDLK_R,
    s = c.SDLK_S,
    t = c.SDLK_T,
    u = c.SDLK_U,
    v = c.SDLK_V,
    w = c.SDLK_W,
    x = c.SDLK_X,
    y = c.SDLK_Y,
    z = c.SDLK_Z,
    _1 = c.SDLK_1,
    _2 = c.SDLK_2,
    _3 = c.SDLK_3,
    _4 = c.SDLK_4,
    _5 = c.SDLK_5,
    _6 = c.SDLK_6,
    _7 = c.SDLK_7,
    _8 = c.SDLK_8,
    _9 = c.SDLK_9,
    _0 = c.SDLK_0,
    escape = c.SDLK_ESCAPE,
    space = c.SDLK_SPACE,
    slash = c.SDLK_SLASH,
    up = c.SDLK_UP,
    down = c.SDLK_DOWN,
    left = c.SDLK_LEFT,
    right = c.SDLK_RIGHT,
    left_alt = c.SDLK_LALT,
    right_alt = c.SDLK_RALT,
    left_ctrl = c.SDLK_LCTRL,
    right_ctrl = c.SDLK_RCTRL,
    left_shift = c.SDLK_LSHIFT,
    right_shift = c.SDLK_RSHIFT,
    left_gui = c.SDLK_LGUI,
    right_gui = c.SDLK_RGUI,

    /// 转换为 SDL 键码
    pub fn code(self: Key) Keycode {
        return @backingInt(self);
    }

    /// 从 SDL 键码解析，未知按键返回 `null`。
    pub fn from(key: Keycode) ?Key {
        return std.enums.fromInt(Key, key);
    }

    /// 从字符串解析按键名，未知按键返回 `null`。注意：数字键不需要 `_` 前缀。
    pub fn parse(name: []const u8) ?Key {
        // 枚举字段不能以数字开头，数字键的枚举名带 _ 前缀
        if (name.len == 1 and std.ascii.isDigit(name[0])) { // 仅处理单个数字的字符串
            const prefixed = [2]u8{ '_', name[0] };
            return std.meta.stringToEnum(Key, &prefixed);
        }
        return std.meta.stringToEnum(Key, name);
    }

    /// 判断 SDL 键码是否为当前按键。
    pub fn matches(self: Key, key: Keycode) bool {
        return self.code() == key;
    }
};
