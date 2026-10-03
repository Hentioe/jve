const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const Size = @import("structs.zig").Size(u32);
const Image = @import("../root.zig").loader.Image;
const Self = @This();

pub fn createTexture(
    device: *c.SDL_GPUDevice,
    create_info: *const c.SDL_GPUTextureCreateInfo,
    pixels_ptr: *const anyopaque,
    size: Size,
) Error!*c.SDL_GPUTexture {
    // 创建 GPU 纹理
    const texture = c.SDL_CreateGPUTexture(device, create_info) orelse return Error.SdlCreateGPUTextureFailed;
    // 将像素数据上传至 GPU
    const buffer_size: u32 = @intCast(size.w * size.h * 4); // RGBA8888 字节大小
    const transfer_info = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD, // 指定为 UPLOAD 模式，即 CPU -> GPU
        .size = buffer_size,
    };
    // 创建传输缓冲区
    const transfer_buf = c.SDL_CreateGPUTransferBuffer(device, &transfer_info);
    defer c.SDL_ReleaseGPUTransferBuffer(device, transfer_buf); // 释放传输缓存
    // 映射内存，复制像素数据至传输缓冲区
    const map_ptr = c.SDL_MapGPUTransferBuffer(device, transfer_buf, false);
    _ = c.SDL_memcpy(map_ptr, pixels_ptr, buffer_size); // 执行复制（像素数据指针作为拷贝源）
    c.SDL_UnmapGPUTransferBuffer(device, transfer_buf); // 解除映射
    // 创建 Command Buffer 并开启复制通道，将传输缓冲区的数据写入纹理
    const cmd_buf = c.SDL_AcquireGPUCommandBuffer(device);
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buf);
    const src = c.SDL_GPUTextureTransferInfo{
        .transfer_buffer = transfer_buf,
        .offset = 0,
    };
    const dst = c.SDL_GPUTextureRegion{
        .texture = texture,
        .w = @intCast(size.w),
        .h = @intCast(size.h),
        .d = 1,
    };
    // 提交上传命令
    c.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);
    c.SDL_EndGPUCopyPass(copy_pass); // 结束复制通道
    if (!h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf))) return Error.SdlSubmitGPUCommandBufferFailed;

    return texture;
}
