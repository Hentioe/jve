const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Self = @This();

gpu_device: *c.SDL_GPUDevice,

pub fn create() Error!Self {
    // 声明格式 flags
    const flags = c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL;
    // 创建 GPU 设备
    const device = try h.check(c.SDL_CreateGPUDevice(flags, false, null));

    return Self{
        .gpu_device = device,
    };
}

pub fn destroy(self: *Self) void {
    c.SDL_DestroyGPUDevice(self.gpu_device);
    self.* = undefined;
}

// 由于外部无需传递 GPU 设备指针，所以名称中的 ForGPUDevice 是多余的。其它情况保留原 API 命名风格。
pub fn claimWindow(self: *const Self, window: *c.SDL_Window) Error!void {
    try h.check(c.SDL_ClaimWindowForGPUDevice(self.gpu_device, window));
}

// 窗口销毁前必须先从设备解绑。
pub fn releaseWindow(self: *const Self, window: *c.SDL_Window) void {
    c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, window);
}

pub fn getGPUSwapchainTextureFormat(self: *const Self, window: *c.SDL_Window) c.SDL_GPUTextureFormat {
    return c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, window);
}

pub fn createGPUShader(self: *const Self, create_info: *const c.SDL_GPUShaderCreateInfo) Error!*c.SDL_GPUShader {
    return try h.check(c.SDL_CreateGPUShader(self.gpu_device, create_info));
}

pub fn releaseGPUShader(self: *const Self, shader: ?*c.SDL_GPUShader) void {
    c.SDL_ReleaseGPUShader(self.gpu_device, shader);
}

pub fn compileGraphicsShaderFromSPIRV(
    self: *const Self,
    info: *const c.SDL_ShaderCross_SPIRV_Info,
    resource_info: *const c.SDL_ShaderCross_GraphicsShaderResourceInfo,
    props: c.SDL_PropertiesID,
) Error!*c.SDL_GPUShader {
    return try h.check(c.SDL_ShaderCross_CompileGraphicsShaderFromSPIRV(self.gpu_device, info, resource_info, props));
}

pub fn createGPUGraphicsPipeline(self: *const Self, create_info: *const c.SDL_GPUGraphicsPipelineCreateInfo) Error!*c.SDL_GPUGraphicsPipeline {
    return try h.check(c.SDL_CreateGPUGraphicsPipeline(self.gpu_device, create_info));
}

pub fn releaseGPUGraphicsPipeline(self: *const Self, pipeline: ?*c.SDL_GPUGraphicsPipeline) void {
    c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, pipeline);
}

pub fn createGPUTexture(self: *const Self, create_info: *const c.SDL_GPUTextureCreateInfo) Error!*c.SDL_GPUTexture {
    return try h.check(c.SDL_CreateGPUTexture(self.gpu_device, create_info));
}

pub fn releaseGPUTexture(self: *const Self, texture: ?*c.SDL_GPUTexture) void {
    c.SDL_ReleaseGPUTexture(self.gpu_device, texture);
}

pub fn createGPUSampler(self: *const Self, create_info: *const c.SDL_GPUSamplerCreateInfo) Error!*c.SDL_GPUSampler {
    return try h.check(c.SDL_CreateGPUSampler(self.gpu_device, create_info));
}

pub fn releaseGPUSampler(self: *const Self, sampler: ?*c.SDL_GPUSampler) void {
    c.SDL_ReleaseGPUSampler(self.gpu_device, sampler);
}

pub fn createGPUBuffer(self: *const Self, create_info: *const c.SDL_GPUBufferCreateInfo) Error!*c.SDL_GPUBuffer {
    return try h.check(c.SDL_CreateGPUBuffer(self.gpu_device, create_info));
}

pub fn releaseGPUBuffer(self: *const Self, buffer: ?*c.SDL_GPUBuffer) void {
    c.SDL_ReleaseGPUBuffer(self.gpu_device, buffer);
}

pub fn createGPUTransferBuffer(self: *const Self, create_info: *const c.SDL_GPUTransferBufferCreateInfo) Error!*c.SDL_GPUTransferBuffer {
    return try h.check(c.SDL_CreateGPUTransferBuffer(self.gpu_device, create_info));
}

pub fn releaseGPUTransferBuffer(self: *const Self, buffer: ?*c.SDL_GPUTransferBuffer) void {
    c.SDL_ReleaseGPUTransferBuffer(self.gpu_device, buffer);
}

pub fn mapGPUTransferBuffer(self: *const Self, buffer: ?*c.SDL_GPUTransferBuffer, cycle: bool) Error!*anyopaque {
    return try h.check(c.SDL_MapGPUTransferBuffer(self.gpu_device, buffer, cycle));
}

pub fn unmapGPUTransferBuffer(self: *const Self, buffer: ?*c.SDL_GPUTransferBuffer) void {
    c.SDL_UnmapGPUTransferBuffer(self.gpu_device, buffer);
}

pub fn acquireGPUCommandBuffer(self: *const Self) Error!*c.SDL_GPUCommandBuffer {
    return try h.check(c.SDL_AcquireGPUCommandBuffer(self.gpu_device));
}

pub fn waitForGPUIdle(self: *const Self) Error!void {
    try h.check(c.SDL_WaitForGPUIdle(self.gpu_device));
}

pub fn beginRenderPass(cmd_buf: *c.SDL_GPUCommandBuffer, color_target: *c.SDL_GPUColorTargetInfo, color_target_count: u32, depth_stencil_target: ?*c.SDL_GPUDepthStencilTargetInfo) Error!*c.SDL_GPURenderPass {
    return try h.check(c.SDL_BeginGPURenderPass(cmd_buf, color_target, color_target_count, depth_stencil_target));
}

pub fn submitCommandBuffer(cmd_buf: *c.SDL_GPUCommandBuffer) Error!void {
    try h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf));
}

pub fn acquireSwapchainTexture(cmd_buf: *c.SDL_GPUCommandBuffer, window: *c.SDL_Window, swapchain_texture: *?*c.SDL_GPUTexture, width: [*c]u32, height: [*c]u32) bool {
    return c.SDL_AcquireGPUSwapchainTexture(cmd_buf, window, swapchain_texture, width, height);
}
