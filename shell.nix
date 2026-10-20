with import <nixpkgs> { };
let
  # 覆盖 Zig 命令，使用 zvm 运行 Zig
  custom-zig = writeShellScriptBin "zig" "exec zvm run 0.15.2 $@";
  # 启用 ROCm 支持的 ONNX Runtime（此处暂时禁用）
  onnxruntime-rocm = (onnxruntime.override { rocmSupport = false; });
  # 本地开发所需工具
  nativeTools = [
    custom-zig # 受 zvm 管理的 Zig
    zon2nix # 转换 Zig 依赖为 Nix 依赖
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
    libGL # SDL 依赖
    vulkan-loader # Vulkan
  ];
in
mkShell {
  packages = nativeTools ++ runtimeTools ++ runtimeLibs;

  buildInputs = [
    vips # 图像解码
    glib # VIPS 依赖
    onnxruntime-rocm # ONNX 推理引擎
    shader-slang # slang 着色器支持
    libass # 文字支持
  ];

  ZVM_SET_CU = 1; # 禁止 zvm 升级检查
}
