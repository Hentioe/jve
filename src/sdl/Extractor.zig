const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const writer = @import("../root.zig").writer;
const Error = @import("errors.zig").Error;
const Self = @This();

allocator: std.mem.Allocator,
device: *c.SDL_GPUDevice,
width: u32,
height: u32,
bands: u32,
buffer_size: u32,
pixels_slice: ?[]u8 = null,
downloaded: bool = false,

pub fn init(allocator: std.mem.Allocator, device: *c.SDL_GPUDevice, width: i32, height: i32, bands: i32) Self {
    const w_u32: u32 = @intCast(width);
    const h_u32: u32 = @intCast(height);
    const bands_u32: u32 = @intCast(bands);
    return Self{
        .allocator = allocator,
        .device = device,
        .width = w_u32,
        .height = h_u32,
        .bands = bands_u32,
        .buffer_size = w_u32 * h_u32 * bands_u32,
    };
}

pub fn deinit(self: *Self) void {
    if (self.pixels_slice) |slice| {
        self.allocator.free(slice);
        self.pixels_slice = null;
        self.downloaded = false;
    }
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
        .w = self.width,
        .h = self.height,
        .d = 1,
    };
    const dst_transfer: c.SDL_GPUTextureTransferInfo = .{
        .transfer_buffer = download_buffer,
        .offset = 0,
        .pixels_per_row = self.width,
        .rows_per_layer = self.height,
    };
    // 执行下载与复制
    c.SDL_DownloadFromGPUTexture(download_pass, &src_region, &dst_transfer);
    c.SDL_EndGPUCopyPass(download_pass);
    _ = c.SDL_SubmitGPUCommandBuffer(cmd_buf);
    // 3. 等待 GPU 完成
    _ = c.SDL_WaitForGPUIdle(self.device);
    // 4. 映射缓冲区
    const mapped_ptr = c.SDL_MapGPUTransferBuffer(self.device, download_buffer, false) orelse {
        h.printError();
        return Error.SdlMapGPUTransferBufferFailed;
    };
    defer c.SDL_UnmapGPUTransferBuffer(self.device, download_buffer); // 解除映射
    const u8_ptr: [*]u8 = @ptrCast(mapped_ptr);
    const u8_slice: []u8 = u8_ptr[0..self.buffer_size];
    // 5. 将像素数据复制到堆内存（传输缓存区会被释放）
    const piexls_slice = try self.allocator.alloc(u8, self.buffer_size);
    @memcpy(piexls_slice, u8_slice);
    self.pixels_slice = piexls_slice;

    self.downloaded = true;
}

pub fn getAndCheckDataPtr(self: *const Self) Error!*anyopaque {
    if (self.downloaded == false) {
        return Error.NotDownloaded;
    }
    if (self.pixels_slice) |slice| {
        return slice.ptr;
    } else {
        return Error.NoPixelData;
    }
}
