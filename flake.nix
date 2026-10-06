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
        vulkan-loader
        libGL
        wayland
        libxkbcommon
        # 如果用 X11，按需取消注释（不同 nixpkgs 版本里包名可能是 xorg.libX11 或 libx11，以实际为准）
        # libx11
        # libxext
        # libxcursor
        # libxi
        # libxrandr
      ];

      # 程序运行时调用的外部命令（剪贴板）
      runtimeTools = with pkgs; [
        wl-clipboard
        xclip
      ];
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        pname = "jve";
        version = "0.0.0";

        src = ./.;

        nativeBuildInputs = with pkgs; [
          zig_0_15
          pkg-config
          sdl3-shadercross # 提供 shadercross 命令
          makeBinaryWrapper # 用于 postFixup 里的 wrapProgram
        ];

        buildInputs = with pkgs; [
          vips
          glib
          sdl3-shadercross
          vulkan-loader
          libGL
          onnxruntime
        ];

        zigBuildFlags = [
          "-Dcpu=baseline"
          "-Doptimize=ReleaseFast"
        ];
        dontSetZigDefaultFlags = true;

        # 将事先由 zon2nix 生成的依赖目录接入 Zig 包缓存
        postConfigure = ''
          ln -s ${pkgs.callPackage ./build.zig.zon.nix { }} $ZIG_GLOBAL_CACHE_DIR/p
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

      devShells.${system}.default = pkgs.mkShell {
        packages =
          with pkgs;
          [
            zig_0_15
            pkg-config
          ]
          ++ runtimeTools;

        buildInputs = with pkgs; [
          vips
          glib
          sdl3-shadercross
          vulkan-loader
          libGL
          onnxruntime
        ];

        # 让 zig build run 出来的程序也能 dlopen 到这些库
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;
      };
    };
}
