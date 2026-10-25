const std = @import("std");
const c = @import("sdl").c;
const h = @import("sdl").h;
const shared = @import("shared");
const Allocator = std.mem.Allocator;
const Error = @import("errors.zig").Error;
const Gpu = @import("sdl").Gpu;
const TexSize = shared.Size2D(u32);
const Self = @This();

/// 上传数据的来源。`borrowed` 由调用方在 submit 前保持有效；
/// `owned` 由上传器持有，submit/discard 后自动释放。
const Storage = union(enum) {
    borrowed: *const anyopaque,
    owned: []u8,

    fn ptr(self: Storage) *const anyopaque {
        return switch (self) {
            .borrowed => |p| p,
            .owned => |bytes| @ptrCast(bytes.ptr),
        };
    }

    fn free(self: Storage, allocator: Allocator) void {
        switch (self) {
            .borrowed => {},
            .owned => |bytes| allocator.free(bytes),
        }
    }
};

/// 内部纹理上传任务记录
const TextureUploadTask = struct {
    texture: *c.SDL_GPUTexture,
    data: Storage,
    size: TexSize,
    buffer_size: u32,
    aligned_size: u32,
    /// true 时循环纹理，避免覆盖仍在被上一帧命令使用的数据。
    cycle: bool,
};

/// 内部顶点/数据缓冲上传任务记录
const BufferUploadTask = struct {
    buffer: *c.SDL_GPUBuffer,
    data: Storage,
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
            .texture => |t| t.data.ptr(),
            .buffer => |b| b.data.ptr(),
        };
    }

    /// 释放任务持有的数据（仅 `owned` 需要）
    fn free(self: UploadTask, allocator: Allocator) void {
        switch (self) {
            .texture => |t| t.data.free(allocator),
            .buffer => |b| b.data.free(allocator),
        }
    }
};

allocator: Allocator,
gpu: *const Gpu,
tasks: std.ArrayListUnmanaged(UploadTask),

pub fn init(allocator: Allocator, gpu: *const Gpu) Self {
    return .{
        .gpu = gpu,
        .allocator = allocator,
        .tasks = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.discard();
    self.tasks.deinit(self.allocator);
}

/// 丢弃所有未提交的任务，并释放 `owned` 数据。已创建的 GPU 资源仍由调用方负责释放。
pub fn discard(self: *Self) void {
    for (self.tasks.items) |task| task.free(self.allocator);
    self.tasks.clearRetainingCapacity();
}

/// 记录一个纹理上传任务，并立即返回创建好的 GPU 纹理句柄。
/// 注意：pixels_ptr 指向的内存数据必须在调用 submit() 之前保持有效。
pub fn uploadTextureBorrowed(
    self: *Self,
    create_info: *const c.SDL_GPUTextureCreateInfo,
    pixels_ptr: *const anyopaque,
    size: TexSize,
) Error!*c.SDL_GPUTexture {
    return self.addTexture(create_info, .{ .borrowed = pixels_ptr }, size, false);
}

/// 与 `uploadTextureBorrowed` 相同，但会复制一份像素数据由上传器持有，
/// 因此调用方无需保证数据在 submit 前存活。
pub fn uploadTextureOwned(
    self: *Self,
    create_info: *const c.SDL_GPUTextureCreateInfo,
    pixels: []const u8,
) Error!*c.SDL_GPUTexture {
    const copy = try self.allocator.dupe(u8, pixels);
    errdefer self.allocator.free(copy);
    const size = TexSize{ .w = create_info.width, .h = create_info.height };
    return self.addTexture(create_info, .{ .owned = copy }, size, false);
}

/// 更新一个已存在的纹理，不创建新的 GPU 纹理。
/// 注意：pixels_ptr 指向的内存必须在调用 submit() 之前保持有效。
pub fn updateTextureBorrowed(
    self: *Self,
    texture: *c.SDL_GPUTexture,
    pixels_ptr: *const anyopaque,
    size: TexSize,
) Error!void {
    // 计算 RGBA8888 字节大小并做 4 字节对齐
    const raw_size: u32 = @intCast(size.w * size.h * 4);
    const aligned_size = std.mem.alignForward(u32, raw_size, 4);

    try self.tasks.append(self.allocator, .{ .texture = .{
        .texture = texture,
        .data = .{ .borrowed = pixels_ptr },
        .size = size,
        .buffer_size = raw_size,
        .aligned_size = aligned_size,
        .cycle = true,
    } });
}

fn addTexture(self: *Self, create_info: *const c.SDL_GPUTextureCreateInfo, data: Storage, size: TexSize, cycle: bool) Error!*c.SDL_GPUTexture {
    // 计算 RGBA8888 字节大小并做 4 字节对齐
    const raw_size: u32 = @intCast(size.w * size.h * 4);
    const aligned_size = std.mem.alignForward(u32, raw_size, 4);

    const texture = try self.gpu.createGPUTexture(create_info);
    errdefer self.gpu.releaseGPUTexture(texture);

    try self.tasks.append(self.allocator, .{ .texture = .{
        .texture = texture,
        .data = data,
        .size = size,
        .buffer_size = raw_size,
        .aligned_size = aligned_size,
        .cycle = cycle,
    } });

    return texture;
}

/// 记录一个 GPU 缓冲（顶点、索引等）上传任务，并立即返回创建好的 GPU 缓冲句柄。
/// create_info.size 应与 size 一致；size 为数据实际字节大小。
/// 注意：data_ptr 指向的内存数据必须在调用 submit() 之前保持有效。
pub fn uploadBufferBorrowed(
    self: *Self,
    create_info: *const c.SDL_GPUBufferCreateInfo,
    data_ptr: *const anyopaque,
    size: u32,
) Error!*c.SDL_GPUBuffer {
    return self.addBuffer(create_info, .{ .borrowed = data_ptr }, size);
}

/// 与 `uploadBufferBorrowed` 相同，但会复制一份数据由上传器持有，
/// 因此调用方无需保证数据在 submit 前存活。
pub fn uploadBufferOwned(
    self: *Self,
    create_info: *const c.SDL_GPUBufferCreateInfo,
    data: []const u8,
) Error!*c.SDL_GPUBuffer {
    const copy = try self.allocator.dupe(u8, data);
    errdefer self.allocator.free(copy);
    return self.addBuffer(create_info, .{ .owned = copy }, @intCast(copy.len));
}

fn addBuffer(self: *Self, create_info: *const c.SDL_GPUBufferCreateInfo, data: Storage, size: u32) Error!*c.SDL_GPUBuffer {
    // 做 4 字节对齐
    const aligned_size = std.mem.alignForward(u32, size, 4);

    const buffer = try self.gpu.createGPUBuffer(create_info);
    errdefer self.gpu.releaseGPUBuffer(buffer);

    try self.tasks.append(self.allocator, .{ .buffer = .{
        .buffer = buffer,
        .data = data,
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
        .props = 0,
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
                    .pixels_per_row = 0,
                    .rows_per_layer = 0,
                };
                const dst = c.SDL_GPUTextureRegion{
                    .texture = t.texture,
                    .w = t.size.w,
                    .h = t.size.h,
                    .d = 1,
                    .x = 0,
                    .y = 0,
                    .z = 0,
                    .layer = 0,
                    .mip_level = 0,
                };

                c.SDL_UploadToGPUTexture(copy_pass, &src, &dst, t.cycle);
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

    // 7. 清空已完成的任务列表并释放 owned 数据（保留容量供下次复用）
    self.discard();
}
