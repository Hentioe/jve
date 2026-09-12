with import <nixpkgs> { };

mkShell {
  buildInputs = [
    pkg-config
    vips # 图像解码
    glib # vips 依赖
    libGL # SDL 依赖
  ];
}
