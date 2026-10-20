const std = @import("std");
const SdlError = @import("sdl").Error;
const ShaderError = @import("../shader.zig").Error;

pub const CustomError = error{
    PipelineRegistryNotInitialized, // 会话级管线注册表尚未初始化
};

pub const Error = CustomError || SdlError || ShaderError || std.mem.Allocator.Error;
