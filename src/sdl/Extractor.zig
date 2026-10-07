const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const shared = @import("shared");
const Error = @import("errors.zig").Error;
const IShape = shared.IShape;
const Self = @This();

allocator: std.mem.Allocator,
device: *c.SDL_GPUDevice,
shape: IShape(u32),
buffer_size: u32,
pixels_slice: []u8 = undefined,
downloaded: bool = false,

pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, shape: IShape(i32)) Self {
    const u_shape = shape.to(u32);
    return Self{
        .allocator = allocator,
        .device = device,
        .shape = u_shape,
        .buffer_size = u_shape.w * u_shape.h * u_shape.c,
    };
}

pub fn deinit(self: *Self) void {
    if (self.downloaded) self.allocator.free(self.pixels_slice);
    self.* = undefined;
}

pub fn downloadTexture(self: *Self, texture: ?*c.SDL_GPUTexture) Error!void {
    // 1. 创建用于接收像素的下载缓冲区
    const buffer_create_info: c.SDL_GPUTransferBufferCreateInfo = .{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
        .size = self.buffer_size,
    };
    const download_buffer = c.SDL_CreateGPUTransferBuffer(self.device, &buffer_create_info);
    defer c.SDL_ReleaseGPUTransferBuffer(self.device, download_buffer); // 释放缓冲区
    // 2. 提交回读命令
    const cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.device);
    const download_pass = c.SDL_BeginGPUCopyPass(cmd_buf);
    const src_region: c.SDL_GPUTextureRegion = .{
        .texture = texture,
        .w = self.shape.w,
        .h = self.shape.h,
        .d = 1,
    };
    const dst_transfer: c.SDL_GPUTextureTransferInfo = .{
        .transfer_buffer = download_buffer,
        .offset = 0,
        .pixels_per_row = self.shape.w,
        .rows_per_layer = self.shape.h,
    };
    // 执行下载与复制
    c.SDL_DownloadFromGPUTexture(download_pass, &src_region, &dst_transfer);
    c.SDL_EndGPUCopyPass(download_pass);
    // 提交 GPU 命令缓冲区
    try h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf));
    // 3. 等待 GPU 完成
    try h.check(c.SDL_WaitForGPUIdle(self.device));
    // 4. 映射缓冲区
    const mapped_ptr = try h.check(c.SDL_MapGPUTransferBuffer(self.device, download_buffer, false));
    defer c.SDL_UnmapGPUTransferBuffer(self.device, download_buffer); // 解除映射
    const u8_ptr: [*]u8 = @ptrCast(mapped_ptr);
    const u8_slice: []u8 = u8_ptr[0..self.buffer_size];
    // 5. 将像素数据复制到堆内存（传输缓存区会被释放）
    const piexls_slice = try self.allocator.alloc(u8, self.buffer_size);
    @memcpy(piexls_slice, u8_slice);
    self.pixels_slice = piexls_slice;
    self.downloaded = true;
}

pub fn extract(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, texture: ?*c.SDL_GPUTexture, shape: IShape(i32)) Error!Self {
    var extractor = Self.init(allocator, device, shape);
    // 立即下载
    try extractor.downloadTexture(texture);
    // 返回提取器
    return extractor;
}

// todo 有待删除
pub fn getAndCheckDataPtr(self: *const Self) Error!*anyopaque {
    if (self.downloaded == false) {
        return Error.NotDownloaded;
    }
    return self.pixels_slice.ptr;
}
