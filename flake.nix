{
  description = "JVE - GPU-accelerated image viewer with custom shader pipelines and local AI models";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      onnxruntime = pkgs.onnxruntime.override {
        rocmSupport = false;
        cudaSupport = false;
      };

      # 给 webpload 补上 sequential flag，避免 n=-1 打开整段动画时，
      # libvips 在第一次访问像素时把整条 roll 物化（全量解码 + 临时文件）。
      vips = pkgs.vips.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/libvips-webp-sequential.patch ];
      });

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
      zigDeps = pkgs.callPackage ./build.zig.zon.nix { };
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "jve";
        version = "0.0.0";

        src = ./.;

        nativeBuildInputs = with pkgs; [
          zig_0_17
          pkg-config
          makeBinaryWrapper # 用于 postFixup 里的 wrapProgram
        ];

        buildInputs = with pkgs; [
          vips
          glib
          onnxruntime
          shader-slang
          libass
        ];

        # 解决 slang 的构建问题（仅在内建 slang 编译时存在）：
        # - p 目录是链接，解析问题导致 slang-fiddle: FileNotFound
        # - unable to open file for writing: source/slang/core.meta.slang.temp.h
        # preBuild = ''
        #   p="$ZIG_GLOBAL_CACHE_DIR/p"
        #   cp -rL --no-preserve=mode "$(readlink -f "$p")" "$p.new"
        #   rm -rf "$p"
        #   mv "$p.new" "$p"
        # '';
        # 注意：由于 Zig 从 0.15.2 升级到 0.17，问题细节可能已经变化了，但类似问题仍可能存在。

        postPatch = pkgs.lib.concatMapStrings (p: ''
          cp -rsL --no-preserve=mode ${zigDeps}/${p} fork-${p}
        '') zigDeps.pathDependencyPackages;

        zigBuildFlags = [
          "--system"
          "${zigDeps}"
          "-Dcpu=baseline"
          "-Doptimize=ReleaseFast"
          "-Dslang-mode=system" # 动态链接系统 slang 库
        ]
        ++ map (p: "--fork=fork-${p}") zigDeps.pathDependencyPackages;
        zigCheckFlags = finalAttrs.zigBuildFlags;
        dontSetZigDefaultFlags = true;

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
      });

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/jve";
      };
    };
}
