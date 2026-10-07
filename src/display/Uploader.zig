const std = @import("std");
const c = @import("sdl").c;
const h = @import("sdl").h;
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
const ISize = shared.ISize(u32);
const Self = @This();

/// 内部纹理上传任务记录
const TextureUploadTask = struct {
    texture: *c.SDL_GPUTexture,
    pixels_ptr: *const anyopaque,
    size: ISize,
    buffer_size: u32,
    aligned_size: u32,
};

/// 内部顶点/数据缓冲上传任务记录
const BufferUploadTask = struct {
    buffer: *c.SDL_GPUBuffer,
    data_ptr: *const anyopaque,
    buffer_size: u32,
    aligned_size: u32,
};

/// 上传任务：可以是纹理或普通 GPU 缓冲（顶点、索引等）
const UploadTask = union(enum) {
    texture: TextureUploadTask,
    buffer: BufferUploadTask,

    /// 实际数据字节大小（不含对齐填充）
    fn dataSize(self: UploadTask) u32 {
        return switch (self) {
            .texture => |t| t.buffer_size,
            .buffer => |b| b.buffer_size,
        };
    }

    /// 在汇总传输缓冲区中占用的对齐后字节大小
    fn alignedSize(self: UploadTask) u32 {
        return switch (self) {
            .texture => |t| t.aligned_size,
            .buffer => |b| b.aligned_size,
        };
    }

    /// 指向 CPU 端待上传数据的指针
    fn dataPtr(self: UploadTask) *const anyopaque {
        return switch (self) {
            .texture => |t| t.pixels_ptr,
            .buffer => |b| b.data_ptr,
        };
    }
};

allocator: Allocator,
gpu: *Gpu,
tasks: std.ArrayListUnmanaged(UploadTask),

pub fn init(allocator: Allocator, gpu: *Gpu) Self {
    return .{
        .gpu = gpu,
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
    size: ISize,
) Error!*c.SDL_GPUTexture {
    // 1. 创建 GPU 纹理资源
    const texture = try self.gpu.createGPUTexture(create_info);

    // 2. 计算 RGBA8888 字节大小并做 4 字节对齐
    const raw_size: u32 = @intCast(size.w * size.h * 4);
    const aligned_size = std.mem.alignForward(u32, raw_size, 4);

    // 3. 暂存上传任务信息
    try self.tasks.append(self.allocator, .{ .texture = .{
        .texture = texture,
        .pixels_ptr = pixels_ptr,
        .size = size,
        .buffer_size = raw_size,
        .aligned_size = aligned_size,
    } });

    return texture;
}

/// 记录一个 GPU 缓冲（顶点、索引等）上传任务，并立即返回创建好的 GPU 缓冲句柄。
/// create_info.size 应与 size 一致；size 为数据实际字节大小。
/// 注意：data_ptr 指向的内存数据必须在调用 submit() 之前保持有效。
pub fn uploadBuffer(
    self: *Self,
    create_info: *const c.SDL_GPUBufferCreateInfo,
    data_ptr: *const anyopaque,
    size: u32,
) Error!*c.SDL_GPUBuffer {
    // 1. 创建 GPU 缓冲资源
    const buffer = try self.gpu.createGPUBuffer(create_info);

    // 2. 做 4 字节对齐
    const aligned_size = std.mem.alignForward(u32, size, 4);

    // 3. 暂存上传任务信息
    try self.tasks.append(self.allocator, .{ .buffer = .{
        .buffer = buffer,
        .data_ptr = data_ptr,
        .buffer_size = size,
        .aligned_size = aligned_size,
    } });

    return buffer;
}

/// 汇总所有暂存的上传任务，分配单个大 TransferBuffer 一次性拷贝并提交到 GPU
pub fn submit(self: *Self) Error!void {
    if (self.tasks.items.len == 0) return;

    // 1. 统计总所需的传输缓冲区字节大小
    var total_buffer_size: u32 = 0;
    for (self.tasks.items) |task| {
        total_buffer_size += task.alignedSize();
    }

    // 2. 一次性创建包含所有数据的传输缓冲区
    const transfer_info = c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = total_buffer_size,
    };
    const transfer_buf = try self.gpu.createGPUTransferBuffer(&transfer_info);
    defer self.gpu.releaseGPUTransferBuffer(transfer_buf);

    // 3. 映射内存，根据各任务计算出的 offset 依次拷贝像素数据
    const map_ptr = try self.gpu.mapGPUTransferBuffer(transfer_buf, false);
    var current_offset: u32 = 0;
    const base_bytes: [*]u8 = @ptrCast(map_ptr);

    for (self.tasks.items) |task| {
        _ = c.SDL_memcpy(base_bytes + current_offset, task.dataPtr(), task.dataSize()); // 此处忽略返回是安全的，它表示 dst 自身
        current_offset += task.alignedSize();
    }
    self.gpu.unmapGPUTransferBuffer(transfer_buf);

    // 4. 获取 Command Buffer 并开启 Copy Pass
    const cmd_buf = try self.gpu.acquireGPUCommandBuffer();
    const copy_pass = try h.check(c.SDL_BeginGPUCopyPass(cmd_buf));

    // 5. 遍历任务，利用不同的 offset 录制上传指令
    current_offset = 0;
    for (self.tasks.items) |task| {
        switch (task) {
            .texture => |t| {
                const src = c.SDL_GPUTextureTransferInfo{
                    .transfer_buffer = transfer_buf,
                    .offset = current_offset,
                };
                const dst = c.SDL_GPUTextureRegion{
                    .texture = t.texture,
                    .w = t.size.w,
                    .h = t.size.h,
                    .d = 1,
                };

                c.SDL_UploadToGPUTexture(copy_pass, &src, &dst, false);
            },
            .buffer => |b| {
                const src = c.SDL_GPUTransferBufferLocation{
                    .transfer_buffer = transfer_buf,
                    .offset = current_offset,
                };
                const dst = c.SDL_GPUBufferRegion{
                    .buffer = b.buffer,
                    .offset = 0,
                    .size = b.buffer_size,
                };

                c.SDL_UploadToGPUBuffer(copy_pass, &src, &dst, false);
            },
        }
        current_offset += task.alignedSize();
    }

    c.SDL_EndGPUCopyPass(copy_pass);

    // 6. 提交命令缓冲区
    try h.check(c.SDL_SubmitGPUCommandBuffer(cmd_buf));

    // 7. 清空已完成的任务列表（保留分配的容量供下次复用）
    self.tasks.clearRetainingCapacity();
}
