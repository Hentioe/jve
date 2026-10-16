{
  description = "JVE - GPU-accelerated image viewer with custom shader pipelines and local AI models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      onnxruntime = pkgs.onnxruntime.override {
        rocmSupport = false;
        cudaSupport = false;
      };

      # SDL 在运行时通过 dlopen 加载的库。
      # 它们不会出现在链接依赖里，所以不会被写进 RPATH，必须通过 LD_LIBRARY_PATH 提供。
      runtimeLibs = with pkgs; [
        libGL
        libxkbcommon
        vulkan-loader
        wayland
        # 如果用 X11，按需取消注释（不同 nixpkgs 版本里包名可能是 xorg.libX11 或 libx11，以实际为准）
        # libx11
        # libxext
        libxcursor
        # libxi
        # libxrandr
      ];

      # 程序运行时调用的外部命令
      runtimeTools = with pkgs; [
        wl-clipboard # Wayland 剪贴板工具
        xclip # X11 剪贴板工具
      ];
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "jve";
        version = "0.0.0";

        src = ./.;

        nativeBuildInputs = with pkgs; [
          zig_0_15
          shader-slang # 提供 slangc（用于编译内建着色器）
          pkg-config
          makeBinaryWrapper # 用于 postFixup 里的 wrapProgram
        ];

        buildInputs = with pkgs; [
          vips
          glib
          onnxruntime
          libass
        ];

        # 解决 slang 的构建问题：
        # - p 目录是链接，解析问题导致 slang-fiddle: FileNotFound
        # - unable to open file for writing: source/slang/core.meta.slang.temp.h
        preBuild = ''
          p="$ZIG_GLOBAL_CACHE_DIR/p"
          cp -rL --no-preserve=mode "$(readlink -f "$p")" "$p.new"
          rm -rf "$p"
          mv "$p.new" "$p"
        '';

        zigBuildFlags = [
          "-Dcpu=baseline"
          "-Doptimize=ReleaseFast"
        ];
        dontSetZigDefaultFlags = true;

        # 将事先由 zon2nix 生成的依赖目录接入 Zig 包缓存
        postConfigure = ''
          ln -s ${
            pkgs.callPackage ./build.zig.zon.nix {
              # zon2nix 用 `nix flake prefetch` 计算 hash（不会拉取 git 子模块），
              # 而 nixpkgs 的 fetchgit 默认 fetchSubmodules = true，遇到带子模块的依赖（目前还没有）时 hash 会对不上，故显式关闭以对齐。
              fetchgit = args: pkgs.fetchgit (args // { fetchSubmodules = false; });
            }
          } $ZIG_GLOBAL_CACHE_DIR/p
        '';

        postInstall = ''
          install -Dm644 share/jve.desktop $out/share/applications/jve.desktop
          for size in 32x32 48x48 64x64 128x128 256x256; do
            install -Dm644 share/icons/$size/apps/jve.png \
              $out/share/icons/hicolor/$size/apps/jve.png
          done
        '';

        # 为可执行文件注入运行时库路径和外部命令路径
        postFixup = ''
          wrapProgram $out/bin/jve \
            --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath runtimeLibs} \
            --prefix PATH : ${pkgs.lib.makeBinPath runtimeTools}
        '';

        meta = with pkgs.lib; {
          description = "GPU-accelerated image viewer with custom shader pipelines and local AI models";
          mainProgram = "jve";
          platforms = [ "x86_64-linux" ];
        };
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/jve";
      };
    };
}
