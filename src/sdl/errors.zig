const std = @import("std");
const AllocatorError = std.mem.Allocator.Error;
const SpawnError = std.Thread.SpawnError;
const OrtError = @import("ort").Error;
const Scanner = @import("../Scanner.zig");

pub const SdlError = error{
    SdlInitFailed,
    SdlShaderCrossInitFailed,
    SdlCreateShaderFailed,
    SdlCreateGPUDeviceFailed,
    SdlCreateWindowFailed,
    SdlClaimWindowForGPUDeviceFailed,
    SdlCreateRendererFailed,
    SdlCreateTextureFailed,
    SdlCreateGPUTextureFailed,
    SdlCreateGPUBufferFailed,
    SdlCreateGPUTransferBufferFailed,
    SdlAcquireGPUCommandBufferFailed,
    SdlBeginGPUCopyPassFailed,
    SdlEndGPUCopyPassFailed,
    SdlLoadFileFailed,
    SdlCompileShaderFailed,
    SdlSetWindowHitTestFailed,
    SdlHideWindowFailed,
    SdlShowWindowFailed,
    SdlSetWindowTitleFailed,
    CreateGPUGraphicsPipelineFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
    SdlMapGPUTransferBufferFailed,
    SdlSetClipboardDataFailed,
    SdlSetRenderVSyncFailed,
    SdlSubmitGPUCommandBufferFailed,
    AlbumError, // todo: 包含 Album 错误集
};

pub const CustomError = error{
    NotDownloaded,
    NoPixelData,
    ModelNotInitialized,
};

pub const SizeError = error{Negative};

pub const Error = SdlError || CustomError || SizeError || AllocatorError || OrtError || SpawnError || std.posix.AccessError || Scanner.Error;
