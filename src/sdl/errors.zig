pub const Error = error{
    SdlInitFailed,
    SdlShaderCrossInitFailed,
    SdlCreateGPUDeviceFailed,
    SdlCreateWindowFailed,
    SdlClaimWindowForGPUDeviceFailed,
    SdlCreateRendererFailed,
    SdlCompileShaderFailed,
    CreateGPUGraphicsPipelineFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
    SdlMapGPUTransferBufferFailed,
    OutOfMemory,
};
