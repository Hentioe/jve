with import <nixpkgs> { };

mkShell {
  buildInputs = [
    pkg-config
    vips # 图像解码
    glib # vips 依赖
    sdl3-shadercross # SDL_shadercross
    vulkan-loader # Vulkan
    libGL # SDL 依赖
  ];
}
