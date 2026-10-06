with import <nixpkgs> { };
let
  # 覆盖 Zig 命令，使用 zvm 运行 Zig
  custom-zig = writeShellScriptBin "zig" "exec zvm run 0.15.2 $@";
  # 启用 ROCm 支持的 ONNX Runtime
  onnxruntime-rocm = (onnxruntime.override { rocmSupport = true; });
in
mkShell {
  packages = [
    custom-zig # 受 zvm 管理的 Zig
    sdl3-shadercross # 提供 shadercross 命令行工具
    zon2nix # 转换 Zig 依赖为 Nix 依赖
    wl-clipboard # Wayland 剪贴板工具
    xclip # X11 剪贴板工具
    pkg-config # 系统库搜索
  ];

  buildInputs = [
    vips # 图像解码
    spirv-cross # SPIRV-Cross C API（SDL_shadercross 依赖）
    directx-shader-compiler # DXC（SDL_shadercross 依赖）
    onnxruntime-rocm # ONNX 推理引擎
    glib # VIPS 依赖
    libGL # SDL 依赖
    vulkan-loader # Vulkan
  ];

  ZVM_SET_CU = 1; # 禁止 zvm 升级检查
}
