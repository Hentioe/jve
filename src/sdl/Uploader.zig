const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Size = @import("structs.zig").Size(u32);
const Self = @This();

/// 内部上传任务记录
const TextureUploadTask = struct {
    texture: *c.SDL_GPUTexture,
    pixels_ptr: *const anyopaque,
    size: Size,
    buffer_size: u32,
    aligned_size: u32,
};

allocator: Allocator,
device: *c.SDL_GPUDevice,
tasks: std.ArrayListUnmanaged(TextureUploadTask),

pub fn init(allocator: Allocator, device: *c.SDL_GPUDevice) Self {
    return .{
        .device = device,
        .allocator = allocator,
        .tasks = .{},
    };
}

pub fn deinit(self: *Self) void {
    self.tasks.deinit(self.allocator);
}

/// 记录一个纹理上传任务，并立即返回创建好的 GPU 纹理句柄。
/// 注意：pixels_ptr 指向的内存数据必须在调用 submit() 之前保持有效。
pub fn uploadTexture(
    self: *Self,
    create_info: *const c.SDL_GPUTextureCreateInfo,
    pixels_ptr: *const anyopaque,
    size: Size,
) Error!*c.SDL_GPUTexture {
    // 1. 创建 GPU 纹理资源
    const texture = c.SDL_CreateGPUTexture(self.device, create_info) orelse return Error.SdlCreateGPUTextureFailed;

    // 2. 计算 RGBA8888 字节大小并做 4 字节对齐
    const raw_size: u32 = @intCast(size.w * size.h * 4);
    const aligned_size = std.mem.alignForward(u32, raw_size, 4);

    // 3. 暂存上传任务信息
    try self.tasks.append(self.allocator, .{
        .texture = texture,
        .pixels_ptr = pixels_ptr,
        .size = size,
        .buffer_size = raw_size,
        .aligned_size = aligned_size,
    });

    return texture;
}

/// 汇总所有暂存的上传任务，分配单个大 TransferBuffer 一次性拷贝并提交到 GPU
pub fn submit(self: *Self) Error!void {
    if (self.tasks.items.len == 0) return;

    // 1. 统计总所需的传输缓冲区字节大小
    var total_buffer_size: u32 = 0;
    for (self.tasks.items) |task| {
        total_buffer_size += task.aligned_size;
    }

    // 2. 一次性创建包含所有数据的传输缓冲区
    const transfer_info = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = total_buffer_size,
    };
    const transfer_buf = c.SDL_CreateGPUTransferBuffer(self.device, &transfer_info) orelse return Error.SdlCreateGPUTransferBufferFailed;
    defer c.SDL_ReleaseGPUTransferBuffer(self.device, transfer_buf);

    // 3. 映射内存，根据各任务计算出的 offset 依次拷贝像素数据
    const map_ptr = c.SDL_MapGPUTransferBuffer(self.device, transfer_buf, false);
    var current_offset: u32 = 0;
    const base_bytes: [*]u8 = @ptrCast(map_ptr);

    for (self.tasks.items) |task| {
        _ = c.SDL_memcpy(base_bytes + current_offset, task.pixels_ptr, task.buffer_size); // 此处忽略返回是安全的，它表示 dst 自身
        current_offset += task.aligned_size;
    }
    c.SDL_UnmapGPUTransferBuffer(self.device, transfer_buf);

    // 4. 获取 Command Buffer 并开启 Copy Pass
    const cmd_buf = c.SDL_AcquireGPUCommandBuffer(self.device) orelse return Error.SdlAcquireGPUCommandBufferFailed;
    const copy_pass = c.SDL_BeginGPUCopyPass(cmd_buf) orelse return Error.SdlBeginGPUCopyPassFailed;

    // 5. 遍历任务，利用不同的 offset 录制上传指令
    current_offset = 0;
    for (self.tasks.items) |task| {
        const src = c.SDL_GPUTextureTransferInfo{
            .transfer_buffer = transfer_buf,
            .offset = current_offset,
        };
        const dst = c.SDL_GPUTextureRegion{
            .texture = task.texture,
            .w = task.size.w,
            .h = task.size.h,
            .d = 1,
        };

        c.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);
        current_offset += task.aligned_size;
    }

    c.SDL_EndGPUCopyPass(copy_pass);

    // 6. 提交命令缓冲区并检查返回状态
    if (!h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf))) return Error.SdlSubmitGPUCommandBufferFailed;

    // 7. 清空已完成的任务列表（保留分配的容量供下次复用）
    self.tasks.clearRetainingCapacity();
}
