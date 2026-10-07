const c = @import("sdl").c;
const shared = @import("shared");
const Error = @import("errors.zig").Error;
const ISize = shared.ISize(u32);
const Uploader = @import("Uploader.zig");

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
