const OrtError = @import("ort").Error;

pub const SdlError = error{
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
    AlbumError, // 相册模块出错
    NoPixelData,
    OutOfMemory,
};

pub const Error = SdlError || OrtError;
