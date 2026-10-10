const std = @import("std");
const sdl = @import("sdl");
const c = sdl.c;
const h = sdl.h;
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Shape = shared.IShape(u32);

pub const Error = sdl.Error || Allocator.Error;

pub const Extracted = struct {
    allocator: Allocator,
    shape: Shape,
    data: []u8,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};

pub fn extract(allocator: Allocator, gpu: *const sdl.Gpu, texture: ?*sdl.GPUTexture, shape: Shape) Error!Extracted {
    const size = shape.calcSize(u8);
    // 创建用于接收像素的下载缓冲区
    const buf_create_info: c.SDL_GPUTransferBufferCreateInfo = .{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = @intCast(size),
    };
    const download_buf = try gpu.createGPUTransferBuffer(&buf_create_info);
    defer gpu.releaseGPUTransferBuffer(download_buf); // 释放缓冲区
    // 获取命令缓冲区并开始复制通道
    const cmd_buf = try gpu.acquireGPUCommandBuffer();
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buf);
    const src: c.SDL_GPUTextureRegion = .{
        .texture = texture,
        .w = shape.w,
        .h = shape.h,
        .d = 1,
    };
    const dst: c.SDL_GPUTextureTransferInfo = .{
        .transfer_buffer = download_buf,
        .offset = 0,
        .pixels_per_row = shape.w,
        .rows_per_layer = shape.h,
    };
    // 执行下载与复制
    c.SDL_DownloadFromGPUTexture(copy_pass, &src, &dst);
    c.SDL_EndGPUCopyPass(copy_pass);
    // 提交命令缓冲区
    try h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf));
    // 等待 GPU 完成
    try gpu.waitForGPUIdle();
    // 映射缓冲区
    const mapped_ptr = try gpu.mapGPUTransferBuffer(download_buf, false);
    defer gpu.unmapGPUTransferBuffer(download_buf); // 解除映射
    const src_ptr: [*]u8 = @ptrCast(mapped_ptr);
    const src_data: []u8 = src_ptr[0..size];
    // 将像素数据复制到堆内存（传输缓存区会被释放）
    const data = try allocator.alloc(u8, size);
    @memcpy(data, src_data);

    return Extracted{
        .allocator = allocator,
        .shape = shape,
        .data = data,
    };
}
