const std = @import("std");
const AllocatorError = std.mem.Allocator.Error;
const SpawnError = std.Thread.SpawnError;
const OrtError = @import("ort").Error;

pub const SdlError = error{
    SdlInitFailed,
    SdlShaderCrossInitFailed,
    SdlCreateGPUDeviceFailed,
    SdlCreateWindowFailed,
    SdlClaimWindowForGPUDeviceFailed,
    SdlCreateRendererFailed,
    SdlCreateTextureFailed,
    SdlLoadFileFailed,
    SdlCompileShaderFailed,
    CreateGPUGraphicsPipelineFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
    SdlMapGPUTransferBufferFailed,
    AlbumError, // todo: 包含 Album 错误集
};

pub const ExtractorError = error{
    NotDownloaded,
    NoPixelData,
};

pub const Error = SdlError || ExtractorError || AllocatorError || OrtError || SpawnError || std.posix.AccessError;
