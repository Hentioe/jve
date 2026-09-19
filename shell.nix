with import <nixpkgs> { };
let
  # 覆盖 Zig 命令，使用 zvm 运行 Zig
  customZig = pkgs.writeShellScriptBin "zig" "exec zvm run 0.15.2 \"$@\"";
in
mkShell {
  buildInputs = [
    customZig # 受 zvm 管理的 Zig
    pkg-config
    vips # 图像解码
    glib # vips 依赖
    sdl3-shadercross # SDL_shadercross
    vulkan-loader # Vulkan
    libGL # SDL 依赖
  ];

  shellHook = ''
    export ZVM_SET_CU=1 # 禁止 zvm 升级检查
  '';
}
