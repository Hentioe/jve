const std = @import("std");
const c = @import("c.zig").c;
const h = @import("helper.zig");
const Error = @import("errors.zig").Error;
const ISize = @import("../structs.zig").ISize(u32);
const Image = @import("../root.zig").loader.Image;
const Uploader = @import("Uploader.zig");
const Self = @This();

/// 创建纹理后，上传并提交到 GPU
pub fn createAndUploadTexture(
    uploader: *Uploader,
    create_info: *const c.SDL_GPUTextureCreateInfo,
    pixels_ptr: *const anyopaque,
    size: ISize,
) Error!*c.SDL_GPUTexture {
    const texture = try uploader.uploadTexture(create_info, pixels_ptr, size);
    try uploader.submit();

    return texture;
}
