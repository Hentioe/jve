pub const Error = error{
    SdlInitFailed,
    SdlShaderCrossInitFailed,
    SdlCreateGPUDeviceFailed,
    SdlClaimWindowForGPUDeviceFailed,
    SdlCompileShaderFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
    OutOfMemory,
};
