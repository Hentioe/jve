with import <nixpkgs> { };

mkShell {
  buildInputs = [
    pkg-config
    vips # 图像解码
    glib # vips 依赖
    sdl3-shadercross # SDL_shadercross
    sdl3-ttf # SDL3_ttf
    vulkan-loader # Vulkan
    libGL # SDL 依赖
  ];
}
