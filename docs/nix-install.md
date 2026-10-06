# 使用 Nix 安装 JVE

## 从本地源码安装

```bash
git clone https://github.com/Hentioe/jve.git
cd jve
nix profile install .
```

## 从远程仓库安装

```bash
nix profile install github:Hentioe/jve
```

固定到某个提交：

```bash
nix profile install github:Hentioe/jve/<commit>
```

## 运行与卸载

```bash
nix run github:Hentioe/jve -- image.png    # 不安装，直接运行
nix profile upgrade jve                    # 更新
nix profile remove jve                     # 卸载
```
