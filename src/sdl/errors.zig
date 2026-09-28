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
    AlbumError, // todo: 包含 Album 错误集
};

pub const ExtractorError = error{
    NotDownloaded,
    NoPixelData,
};

pub const Error = SdlError || ExtractorError || AllocatorError || OrtError || SpawnError || std.posix.AccessError || Scanner.Error;
