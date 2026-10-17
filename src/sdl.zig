const errors = @import("sdl/errors.zig");

pub const c = @import("sdl/c.zig").c;
pub const h = @import("sdl/helper.zig");
pub const check = h.check;
pub const Gpu = @import("sdl/Gpu.zig");
pub const Renderer = @import("sdl/Renderer.zig");
pub const Error = errors.Error;

// -- 类型别名 --
pub const Texture = c.SDL_Texture;
pub const GPUShader = c.SDL_GPUShader;
pub const GPUTexture = c.SDL_GPUTexture;
pub const GPURenderPass = c.SDL_GPURenderPass;
pub const GPUCommandBuffer = c.SDL_GPUCommandBuffer;
pub const Event = c.SDL_Event;
pub const EVENT_QUIT = c.SDL_EVENT_QUIT;
pub const EVENT_MOUSE_BUTTON_DOWN = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
pub const EVENT_MOUSE_BUTTON_UP = c.SDL_EVENT_MOUSE_BUTTON_UP;
pub const HINT_MOUSE_FOCUS_CLICKTHROUGH = c.SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH;
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
