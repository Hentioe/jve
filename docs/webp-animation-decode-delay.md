# WebP 动图首次播放延迟调查

## 结论

延迟来自 **libvips 的 WebP 动画加载行为**，不是渲染、Playback 或纹理上传。

更准确地说：`webpload` 没有声明 `VIPS_FOREIGN_SEQUENTIAL`，libvips 因此把整条动画 roll 当成“非 partial 输出”，在第一次访问像素时一次性物化（解码到内存，或超过阈值时写到临时 `.v` 文件），从而解码全部帧。

还有第二个必要条件：直接调用 `vips_webpload()` 时 `access` 默认是 `VIPS_ACCESS_RANDOM`。即使 loader 声明了 sequential，`vips_foreign_load_temp()` 也只在 `access != VIPS_ACCESS_RANDOM` 时才走 partial 路径。因此应用侧必须显式传入 `access=sequential`，否则补丁不会生效。

- 动图容器用 `vips_webpload(path, "n", -1)` 打开整段 roll。
- 打开时只读取元数据，很快。
- 在原版 libvips 上，**第一次访问 roll 像素时会解码整段动画**，即使只请求第 0 页的 1 行像素。修复方式见后文。
- 我们的代码里，第一次访问发生在播放切到 index 1 时：

  ```text
  advanceAnimation
    → Animation.frameAt(1)
    → Animation.extractAt(1)
    → image.allocOutInMemory()   // vips_image_write_to_memory
  ```

- 因此表现为：首帧立即显示，停留 1–2 秒后突然开始播放。
- 首帧本身不慢，因为它来自 gallery 的普通图片加载（`n=1`），此时还没有访问 `Animation` 的 roll。

延迟大小不取决于文件大小，而取决于**解码后的像素量**：

```text
width × page_height × n-pages × 4 字节
```

## 实测

### 应用内日志

用户素材：108 帧、1.6 MB WebP。

```text
debug: First frame render took 1 ms
debug: First animation frame decode started (index 1/108, 0-based)
debug: First animation frame decode took 1016 ms (crop 0 ms, sRGB 0 ms, alpha 0 ms, write_to_memory 1016 ms)
debug: First loop stall: 1017 ms since previous iteration
```

- `First frame render`：渲染 index 0，来自 gallery 的 `n=1` 加载。
- `index 1`：第二个可见帧（索引从 0 开始），也是容器第一次抽帧。
- `crop / sRGB / alpha` 都是 0 ms，因为它们只建立惰性管线。
- 真正触发解码的是 `write_to_memory`，1016 ms 全在这里。
- `First loop stall` 与解码耗时一致，说明整个渲染循环被阻塞。

### vips CLI 对照

测试文件：20 帧、1280×720、1.4 MB WebP，帧间隔 80 ms。

| 操作                     | 耗时   |
| ------------------------ | ------ |
| `n=1` 裁剪第 0 页 1 行   | 0.060s |
| `n=2` 裁剪第 0 页 1 行   | 0.094s |
| `n=4` 裁剪第 0 页 1 行   | 0.157s |
| `n=8` 裁剪第 0 页 1 行   | 0.280s |
| `n=20` 裁剪第 0 页 1 行  | 0.593s |
| `n=20` 裁剪第 10 页 1 行 | 0.606s |
| `n=-1` 完整解码          | 0.624s |
| `page=1` 单页打开        | 0.074s |
| `page=10` 单页打开       | 0.130s |
| `page=19` 单页打开       | 0.191s |
| `n=8, page=0` 打开       | 0.281s |
| `n=8, page=8` 打开       | 0.287s |

关键点：

1. 请求**第 0 页的 1 行**，耗时仍随 `n` 线性增长，说明 `n=-1` 的第一次像素访问就是全量解码。
2. 单页打开 `page=i` 的耗时随 `i` 增长，因为 libwebp 需要从第 0 帧顺序解到目标帧，不适合逐帧按需加载。
3. `n=k` 窗口的耗时只与 `k` 有关，与起始页无关；窗口加载是可行的，但边界需要预取。

### GIF 对照

同样 20 帧、1280×720 的 GIF：

| 操作                    | GIF    | WebP   |
| ----------------------- | ------ | ------ |
| `n=1` 裁剪第 0 页 1 行  | 0.039s | 0.056s |
| `n=2` 裁剪第 0 页 1 行  | 0.042s | 0.094s |
| `n=4` 裁剪第 0 页 1 行  | 0.040s | 0.157s |
| `n=8` 裁剪第 0 页 1 行  | 0.041s | 0.280s |
| `n=20` 裁剪第 0 页 1 行 | 0.043s | 0.582s |
| 完整解码                | 0.135s | 0.624s |

GIF 的结果说明它不是“解码快所以感觉不到”，而是**加载方式不同**：

- `gifload` 是真正的按页惰性生成。`n` 从 1 增加到 20，裁剪第 0 页 1 行的耗时几乎不变（约 0.04s）。
- 只有真正请求全部页时，才付出 0.135s。
- 应用里首次切到第 1 帧只需生成第 1 页，所以 GIF 没有首播卡顿。

WebP 则是第一次像素访问就全量解码，`n` 越大耗时越长。因此这个问题是 **WebP 加载器特有的**，不是所有 libvips 动图格式的共性。

其他格式：

- AVIF / HEIC 动图目前不进入 `Animation`，仍只显示第一帧；走 `magickload` 时是另一类“加载阶段整体解码”的问题，见 `docs/avif-load-investigation.md`。
- APNG、JPEG-XL 动图暂未接入 `Animation`；若以后支持，需要分别验证各自 loader 是否按页惰性生成。

## libvips 代码级根因

### loader flags 差异

用 `VIPS_TRACE=1` 可以看到两个 loader 的关键差异：

```text
webpload ... flags=VIPS_FOREIGN_NONE access=VIPS_ACCESS_SEQUENTIAL
gifload  ... flags=VIPS_FOREIGN_SEQUENTIAL access=VIPS_ACCESS_SEQUENTIAL
```

对应源码：

- `libvips/foreign/webpload.c:113-123`

  ```c
  static VipsForeignFlags
  vips_foreign_load_webp_get_flags(VipsForeignLoad *load)
  {
      return 0;
  }

  static VipsForeignFlags
  vips_foreign_load_webp_get_flags_filename(const char *filename)
  {
      return 0;
  }
  ```

- `libvips/foreign/nsgifload.c:184-194`

  ```c
  static VipsForeignFlags
  vips_foreign_load_nsgif_get_flags_filename(const char *filename)
  {
      return VIPS_FOREIGN_SEQUENTIAL;
  }

  static VipsForeignFlags
  vips_foreign_load_nsgif_get_flags(VipsForeignLoad *load)
  {
      return VIPS_FOREIGN_SEQUENTIAL;
  }
  ```

### 调用链

1. 第一次访问像素时，`VipsForeignLoad` 调用 loader 的 `load`。在此之前，它会先用 `vips_foreign_load_temp()` 决定 `load->real` 的类型（`libvips/foreign/foreign.c:914-973`）：

   ```c
   if (load->flags & VIPS_FOREIGN_PARTIAL)
       return vips_image_new();

   if ((load->flags & VIPS_FOREIGN_SEQUENTIAL) &&
       load->access != VIPS_ACCESS_RANDOM)
       return vips_image_new();

   if (image_size > disc_threshold)
       return vips_image_new_temp_file("%s.v");

   return vips_image_new_memory();
   ```

   - GIF 的 flags 含 `VIPS_FOREIGN_SEQUENTIAL`，所以拿到 **partial 图像**。
   - WebP 的 flags 是 0，所以拿到 **内存图像** 或 **临时文件图像**。

2. WebP 的 `read_image()` 把惰性管线写进这个非 partial 图像（`libvips/foreign/webp2vips.c:784-803`）：

   ```c
   if (vips_image_generate(t[0], NULL, read_webp_generate, NULL, read, NULL) ||
       vips_sequential(t[0], &t[1], NULL) ||
       vips_image_write(t[1], out))
   ```

3. `vips_image_write()` 最终调用 `vips_image_generate(out, ...)`（`libvips/iofuncs/image.c:2662-2700`）。

4. `vips_image_generate()` 根据输出图像类型决定是否立即求值（`libvips/iofuncs/generate.c:710-764`）：

   ```c
   case VIPS_IMAGE_PARTIAL:
       /* 只挂回调，保持惰性 */
       break;

   case VIPS_IMAGE_SETBUF:
   case VIPS_IMAGE_OPENOUT:
       /* 立刻求值 */
       if (image->dtype == VIPS_IMAGE_OPENOUT)
           res = vips_sink_disc(image, write_vips, NULL);
       else
           res = vips_sink_memory(image);
   ```

   WebP 的 `out` 不是 partial，因此 `vips_sink_memory()` / `vips_sink_disc()` 会立刻把整条 tall image 生成完，也就是解码全部帧。

所以不是 `read_webp_generate()` 主动循环所有帧，而是 **loader flags 让 libvips 选择了“先物化整条 roll”的路径**。GIF 因为声明了 sequential，走 partial 路径，才表现出按页惰性。

### 100 MiB 临时文件阈值

`vips_get_disc_threshold()` 默认是 100 MiB（`libvips/iofuncs/image.c:2542-2580`）。当 WebP 解码后的 tall image 超过这个值时，`vips_foreign_load_temp()` 会返回 `vips_image_new_temp_file("%s.v")`：

- 先把全部帧解码并写入临时 `.v` 文件；
- 再把文件重新打开，供后续裁剪读取。

因此大动图的首播卡顿不仅包含解码，还可能包含几百 MB 的临时文件写入。108 帧的动图很容易超过 100 MiB。

## 触发点：为什么是 `write_to_memory`

libvips 管线是惰性的：

```text
vips_crop       → 只记录裁剪区域
vips_colourspace → 只记录色彩转换
vips_addalpha   → 只记录 alpha 通道
vips_image_write_to_memory → 真正开始生成像素
```

所以 `crop / sRGB / alpha` 都是 0 ms，耗时全部落在最后一步。第一次 `write_to_memory` 会触发 loader 的 `load`，而 WebP loader 又被 flags 带到了“物化整条 roll”的路径，所以整段动画在这一次调用里解完。

## 能不能避免

在**原版 libvips** 上，全量物化无法消除，只能选择支付时机：

| 方案                               | 首帧呈现          | 首播              | 内存                | 复杂度             |
| ---------------------------------- | ----------------- | ----------------- | ------------------- | ------------------ |
| 当前 lazy（默认）                  | 立即              | 卡 1–2 秒         | roll + 已抽帧       | 已完成             |
| 启动时 warmup                      | 窗口晚 1–2 秒出现 | 立即流畅          | roll + 已抽帧       | 很小               |
| 启动时 preload                     | 窗口晚 1–2 秒出现 | 立即流畅          | 全部帧（释放 roll） | 已有实现，改默认值 |
| `page=i` 逐帧打开                  | 立即              | 每帧耗时随 i 增长 | 低                  | 不可用             |
| `n=k` 窗口 + 后台预取              | 立即              | 接近流畅          | 窗口大小            | 中等               |
| 直接使用 libwebp `WebPAnimDecoder` | 立即              | 立即流畅          | 可逐帧缓存          | 较大               |
| 给 webpload 补 sequential flag     | 立即              | 立即流畅          | 按需                | 低，但需维护 patch |

### 方案说明

- **给 webpload 补 sequential flag**：让 `vips_foreign_load_temp()` 返回 partial 图像，`vips_image_write()` 不再立即 sink，第一次裁剪第 1 页只解到第 1 页。详见下一节。
- **warmup / preload**：把 1–2 秒解码提前到 `RenderDeps.init`，窗口显示时已经就绪。preload 还会释放 roll，避免 roll 与帧缓存双份内存；但需要满足 `width × page_height × 4 × n-pages ≤ 512 MiB`，否则会回退到 lazy。
- **`page=i` 逐帧打开**：虽然首次只解目标帧，但 libwebp 要从第 0 帧顺序解到第 i 帧，越播越慢，不适合实时播放。
- **`n=k` 窗口**：每次只解 k 帧，初次延迟降为原来的 `k / 总帧数`；窗口边界需要在后台预取下一个窗口，否则每次边界都会卡一下。
- **libwebp `WebPAnimDecoder`**：真正的增量解码，解一帧只需几毫秒，可以从根本上消除全量解码和启动等待。需要新增 WebP 动画解码模块，把 `Animation` 的 WebP 路径切过去；GIF 继续走 libvips。

## 修复：给 webpload 补 sequential flag

补丁位于 `patches/libvips-webp-sequential.patch`，并在 `flake.nix` / `shell.nix` 中通过 `overrideAttrs` 应用。

从 `vips_foreign_load_temp()` 的分支可以看到，只要 `webpload` 返回 `VIPS_FOREIGN_SEQUENTIAL`，并且调用方请求 sequential access，就会走 partial 路径：

```c
static VipsForeignFlags
vips_foreign_load_webp_get_flags(VipsForeignLoad *load)
{
    return VIPS_FOREIGN_SEQUENTIAL;
}

static VipsForeignFlags
vips_foreign_load_webp_get_flags_filename(const char *filename)
{
    return VIPS_FOREIGN_SEQUENTIAL;
}
```

### 应用侧必须同时请求 sequential access

只打 loader 补丁还不够。直接调用 `vips_webpload()` 时，`access` 默认是 `VIPS_ACCESS_RANDOM`，`vips_foreign_load_temp()` 仍然会物化整条 roll。`vips crop` CLI 之所以在补丁后立刻变快，是因为它走的是 sequential access；应用侧的 `Animation.openRoll()` 必须显式传入：

```zig
.webp => try h.check(c.vips_webpload(path, &in,
    "n", @as(c_int, -1),
    "access", c.VIPS_ACCESS_SEQUENTIAL,
    VIPS_ARGUMENT_NULL)),
```

GIF 和 JXL 也显式传 `access=sequential`，保证三个格式的读取方式一致。`Animation` 本身只在前进时按顺序抽帧，后退时会重新打开 roll，因此 sequential access 与它的语义一致。

### 验证结果（Nix 补丁）

测试素材：

- `big20.webp`：20 帧、1280×720。
- `anim108.webp`：108 帧、1280×720，解码后约 398 MiB，超过 100 MiB 临时文件阈值。
- `assets/animation-timecode.webp`：上述 108 帧素材的仓库内副本，左上角带时间码和帧号，便于观察播放进度与循环回绕。

CLI 首次裁剪：

| 操作                                | 原版 libvips | 补丁 + sequential access |
| ----------------------------------- | ------------ | ------------------------ |
| `big20.webp[n=20]` 裁第 0 页 1 行   | 0.588s       | 0.041s                   |
| `big20.webp[n=-1]` 裁第 1 页整页    | 0.683s       | 0.166s                   |
| `anim108.webp[n=-1]` 裁第 0 页 1 行 | 3.171s       | 0.041s                   |
| `anim108.webp[n=-1]` 裁第 1 页整页  | —            | 0.100s                   |
| `anim108.webp[n=-1]` 完整解码       | 3.287s       | 3.272s                   |

完整解码耗时基本不变，说明补丁只是把“全量物化”改成“按需生成”，并没有改变单帧解码成本。

应用内首次抽帧（`anim108.webp`，index 1）：

```text
原版：First animation frame decode took 2879 ms (write_to_memory 2879 ms)
补丁：First animation frame decode took 32 ms (write_to_memory 32 ms)
```

应用连续运行 10 秒（108 帧 × 80 ms ≈ 8.64 秒，跨过一次循环回绕），没有再出现 `First loop stall`，也没有抽帧错误。GIF 在同样配置下首次抽帧 13 ms，行为未受影响。

### 仍需注意

- 向后跳帧时，`vips_sequential` 不能倒带；`Animation` 目前对后退会 `reopenRoll`，语义上仍然成立。
- `VIPS_FOREIGN_SEQUENTIAL` 会让 loader 禁用操作缓存（`nocache`）；`Animation` 自己持有 roll，影响有限。
- 上游是否接受这个语义变化需要确认；项目内通过 Nix `overrideAttrs` 维护 patch。
- 补丁依赖 libvips 8.18.7 的 `webpload.c`。升级 libvips 时需要重新检查补丁上下文。

## 建议

1. 采用当前 **Nix 给 webpload 打 sequential flag 补丁** 的方案；应用侧同时显式请求 `access=sequential`。
2. 如果未来 libvips 升级导致补丁失效，或上游不接受这个语义变化：退回到 `preload`（接受窗口晚 1–2 秒出现），或实现 libwebp `WebPAnimDecoder` 增量解码。
3. 不建议把 `page=i` 逐帧打开作为正式方案，它只是把一次大卡顿换成持续的小卡顿。
4. 目前 `Animation.extractAt()` 和 GPU loop 里的首次诊断日志仍保留，用于现场确认首帧耗时；确认稳定后可以移除。

## 复现方式

```bash
# 查看帧数和尺寸
vipsheader -a 'anim.webp' | grep -E 'n-pages|page-height|width|height'

# 首次访问的全量解码成本（即使只裁 1 行）
time vips crop 'anim.webp[n=-1]' /tmp/one.png 0 0 <width> 1

# 单页加载随帧索引增长
time vips copy 'anim.webp[page=1]' /tmp/one.v
time vips copy 'anim.webp[page=50]' /tmp/fifty.v

# 进入带 libvips 补丁的 shell（shell.nix 会构建 patched vips）
nix-shell

# 应用内日志（当前为临时 debug 日志，只在首次解码时输出）
zig build run -- -d gpu anim.webp
```

验证补丁是否生效，可以在应用启动时加 `VIPS_TRACE=1`，确认 `webpload ... flags=VIPS_FOREIGN_SEQUENTIAL`；同时应用侧必须传入 `access=sequential`，否则仍会物化整条 roll。
