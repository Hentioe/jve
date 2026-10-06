const std = @import("std");
const OrtError = @import("ort").Error;
const SizeError = @import("shared").SizeError;
const AlbumError = @import("../album.zig").Error;
const AiError = @import("ai").Error;

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
    SdlSetNumberPropertyFailed,
    SdlBeginRenderPassFailed,
};

pub const CustomError = error{
    NotDownloaded,
    NoPixelData,
    CreateScreenshotDirFailed, // 创建截图目录失败
};

pub const Error = SdlError || CustomError || SizeError || OrtError || AlbumError || AiError ||
    std.mem.Allocator.Error || std.Thread.SpawnError || std.posix.AccessError;
