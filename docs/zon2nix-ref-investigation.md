# zon2nix 对 `?ref=` 依赖处理失败的调查

## 结论

`zon2nix` 生成的 Nix 表达式会**原样保留 `build.zig.zon` 依赖 URL 里的 `?ref=` 查询串**，将其写进 `fetchgit.url`，导致 `fetchgit` 无法解析并报 `is this a git repository?`。

这是 `zon2nix` 的确定性缺陷，**不是网络问题**。规避方式是把依赖 URL 从 `git+...?ref=branch#rev` 改为只带 `#rev` 的 `git+...#rev`：rev 已固定，hash 是内容寻址不受 URL 影响，改后 hash 不变。

## 复现现象

在 `nix build` 阶段，拉取 toml 依赖时失败：

```plaintext
building '...-zig-toml?ref=zig-0.15-475b03c.drv'...
 > exporting https://github.com/sam701/zig-toml?ref=zig-0.15 (rev 475b03c...) into ...
 > fatal: https://github.com/sam701/zig-toml?ref=zig-0.15/info/refs not valid: is this a git repository?
 > Unable to checkout 475b03c... from https://github.com/sam701/zig-toml?ref=zig-0.15
```

`git` 把 `?ref=zig-0.15` 当成了路径的一部分，去请求 `.../zig-toml?ref=zig-0.15/info/refs`，自然 404。

## 根因

`zon2nix` 分两步处理此类依赖，问题出在第二步：

1. **解析**（[`src/Dependency.zig` 的 `fromUrl`](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/Dependency.zig#L26)）：对 `git+https://...?ref=x#rev` 形式的 URL，由 [`urlRev` 分支](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/Dependency.zig#L31)解析为 `parameters = .rev`，但 `.url` 字段**保留了 `?ref=x`**：

   ```zig
   .urlRev => |u| return Dependency{ .url = u.url, .parameters = .{ .rev = u.rev }, ... },
   ```

   其[内置解析测试](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/Dependency.zig#L196)同样保留了 query，可佐证这是预期行为（并非解析 bug）：

   ```zig
   .inputUrl = "git+https://codeberg.org/7Games/zig-sdl3?ref=v0.1.6#9c1842246c59f03f87ba59b160ca7e3d5e5ce972",
   // 解析后 .url = "https://codeberg.org/7Games/zig-sdl3?ref=v0.1.6"
   ```

2. **生成**（[`src/codegen.zig`](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/codegen.zig#L37)）：[`.rev` 分支](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/codegen.zig#L38)直接把 `dep.url` 原样写入 `fetchgit.url`（[第 43 行](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/codegen.zig#L43)）：

   ```nix
   path = fetchgit {
     url = "{s}";   # dep.url，仍带 ?ref=
     rev = "{s}";
     hash = "{s}";
   };
   ```

   代码里其实提供了 [`Dependency.flakePrefetchRef`](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/Dependency.zig#L59)，它会检测 query 并改写为 `?rev=...`（即剥离 `?ref=`）。**但 codegen 的 `.rev` 分支没有调用它**，于是 query 被带进了 `fetchgit`。

与之相对，[`.ref` 分支](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/codegen.zig#L51)会把 ref 拆成独立的 `ref = "..."` 参数，不受影响；只有走 `.rev`（URL 带 `#rev`）的依赖会踩坑。`fetchzip` 分支（[第 69 行](https://github.com/nix-community/zon2nix/blob/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92/src/codegen.zig#L69)，纯 tarball URL）也不受影响。

## 受控复现

用一个最小 `build.zig.zon`（仅 toml 依赖）就能稳定复现：

```bash
nix run nixpkgs#zon2nix -- zontest/build.zig.zon
```

输出中 URL 仍带 query：

```nix
{
  name = "toml-0.3.0-bV14BfV7AQD8DkuQI7skP8ekQTaBYKTO0MY_35Cw_EXo";
  path = fetchgit {
    url = "https://github.com/sam701/zig-toml?ref=zig-0.15";  # ← 问题所在
    rev = "475b03c630c802f8b6bd3e239d8fc2279b4fadb8";
    hash = "sha256-TOW27uDzos3P0K3535TYxogR1o2j5u2BaMHo9vyAbW8=";
  };
}
```

## 验证改动安全性

去掉 `?ref=zig-0.15` 后，用 Zig 实测拉取：

```bash
# build.zig.zon: .url = "git+https://github.com/sam701/zig-toml#475b03c..."
ZIG_GLOBAL_CACHE_DIR=/tmp/refcheck-cache zig build --fetch=all
```

生成的包目录名与声明的 `.hash` 完全一致，说明内容寻址的 hash 与 URL 中的 `ref` 无关：

```plaintext
toml-0.3.0-bV14BfV7AQD8DkuQI7skP8ekQTaBYKTO0MY_35Cw_EXo
```

同时 `zon2nix` 对新 URL 的输出变为干净的 `url = "https://github.com/sam701/zig-toml"`，无需再手工修正生成文件。

## 处置（已实现）

- `build.zig.zon`：toml 依赖改为 `git+https://github.com/sam701/zig-toml#475b03c630c802f8b6bd3e239d8fc2279b4fadb8`（去掉 `?ref=zig-0.15`，rev 与 hash 不变）。
- 依赖变更后重新生成：`nix run nixpkgs#zon2nix -- build.zig.zon > build.zig.zon.nix`。

> 环境：nixpkgs 的 `zon2nix` 0.1.3-unstable-2026-04-13，对应上游修订 [`d1e1762`](https://github.com/nix-community/zon2nix/commit/d1e1762ce1e5d4df3b65a0d45421b6fb7b99cf92)，Zig 0.15.2；上文源码链接均固定到该修订。
