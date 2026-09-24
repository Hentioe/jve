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
    wl-clipboard # Wayland 剪贴板工具
    xclip # X11 剪贴板工具
    pkg-config # 依赖库搜索
  ];

  buildInputs = [
    vips # 图像解码
    glib # vips 依赖
    sdl3-shadercross # SDL_shadercross
    vulkan-loader # Vulkan
    libGL # SDL 依赖
    onnxruntime-rocm # ONNX 推理引擎
  ];

  ZVM_SET_CU = 1; # 禁止 zvm 升级检查
}
