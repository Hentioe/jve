const std = @import("std");
const OrtError = @import("ort").Error;
const ScannerError = @import("../Scanner.zig").Error;
const AlbumError = @import("../album.zig").Error;

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
    SdlCreateGPUGraphicsPipelineFailed,
    SdlSetTextureBlendModeFailed,
    SdlUpdateTextureFailed,
    SdlMapGPUTransferBufferFailed,
    SdlSetClipboardDataFailed,
    SdlSetRenderVSyncFailed,
    SdlSubmitGPUCommandBufferFailed,
    SdlBeginRenderPassFailed,
};

pub const CustomError = error{
    NotDownloaded,
    NoPixelData,
    ModelNotInitialized,
};

pub const SizeError = error{Negative};

pub const Error = SdlError || CustomError || SizeError || OrtError || AlbumError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError;
