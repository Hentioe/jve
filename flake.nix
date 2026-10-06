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
        packages = with pkgs; [
          zig_0_15
          pkg-config
          wl-clipboard
          xclip
        ];

        buildInputs = with pkgs; [
          vips
          glib
          sdl3-shadercross
          vulkan-loader
          libGL
          onnxruntime
        ];
      };
    };
}
