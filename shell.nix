with import <nixpkgs> { };
let
  # 覆盖 Zig 命令，使用 zvm 运行 Zig
  custom-zig = writeShellScriptBin "zig" "exec zvm run 0.15.2 $@";
  # 启用 ROCm 支持的 ONNX Runtime
  onnxruntime-rocm = (onnxruntime.override { rocmSupport = true; });
  # 本地开发所需工具
  nativeTools = [
    custom-zig # 受 zvm 管理的 Zig
    zon2nix # 转换 Zig 依赖为 Nix 依赖
    sdl3-shadercross # 提供 shadercross 命令
    pkg-config # 系统库搜索
  ];
  # 运行时所需工具
  runtimeTools = [
    wl-clipboard # Wayland 剪贴板工具
    xclip # X11 剪贴板工具
  ];
  # 运行时所需库
  runtimeLibs = [
    libxcursor # X11 光标库（避免回退成黑色小光标）
  ];
in
mkShell {
  packages = nativeTools ++ runtimeTools ++ runtimeLibs;

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
