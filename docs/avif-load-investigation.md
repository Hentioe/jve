# AVIF 动图加载卡顿调查

## 结论

`vips_image_new_from_file` 加载 AVIF 动图时并不会主动解码所有帧，而是它**选错了 loader**：AVIF 动图被交给 ImageMagick 的 `magickload`，后者一次性解码整段动画，导致加载阶段卡顿、内存飙升。

原生 `heifload` 只要第一帧，速度快、内存低。

## 根因

1. AVIF 动图的 major brand 是 `avis`（AVIF sequence）：

   ```plaintext
   00 00 00 2c 66 74 79 70 61 76 69 73 ...
   │  size=44 │  ftyp │  a v i s
   ```

2. libvips 8.18.6 的原生 `heifload` 通过 [`is_a()`](https://github.com/libvips/libvips/blob/v8.18.6/libvips/foreign/heifload.c#L406) 嗅探文件头，其 [`heif_magic[]`](https://github.com/libvips/libvips/blob/v8.18.6/libvips/foreign/heifload.c#L385-L396) 白名单只有 [`ftypavif`](https://github.com/libvips/libvips/blob/v8.18.6/libvips/foreign/heifload.c#L395)，**没有 `ftypavis`**：

   ```c
   "ftypmsf1", /* Nokia animation image */
   "ftypavif"  /* AV1 image format */
   ```

   因此 `ftypavis` 匹配失败，原生 heifload 拒绝加载 AVIF 动图。
3. libvips 回退到兜底 loader `magickload`（priority=-100，ImageMagick）。ImageMagick 的 AVIF 解码器会一次性读入整段动画。
4. 卡顿与内存升高发生在**加载阶段**，与渲染器无关（渲染器只收到一张单帧）。

## 背景：`ftypavis` 是什么

`ftyp` 是 ISO BMFF（MP4 / HEIF / AVIF 都基于它）文件开头的 **File Type Box**，结构为：

```plaintext
[4 字节 box 大小] [4 字节 "ftyp"] [4 字节 major_brand] [4 字节 minor_version] [若干 4 字节 compatible_brands]
```

其中 `major_brand` 标明了文件类型。对 AVIF 来说：

- `avif` = AVIF **静态**图片
- `avis` = AVIF **动图序列**（AVIF sequence / animation）

libvips 的嗅探是拿 `buf+4`（即 `"ftyp"` + 4 字节 brand，共 8 字节）去和 `heif_magic[]` 逐条比对，所以白名单里的 `"ftypavif"` 实际匹配的是 major_brand = `avif` 的文件；而 major_brand = `avis` 的动图，其 8 字节签名是 `"ftypavis"`。

**不在白名单意味着**：`is_a()` 判定「这文件不是我的格式」并返回 0，于是 libvips 不再把原生 `heifload` 当作候选 loader，转而回退到兜底的 ImageMagick `magickload`。

## 实测（同一张 AVIF 动图）

| 方式                            | wall  | peak RSS | vips-loader  |
| ------------------------------- | ----- | -------- | ------------ |
| 默认 `vips_image_new_from_file` | 0.52s | 352 MB   | `magickload` |
| `vips heifload ..., "n", 1`     | 0.04s | 46 MB    | `heifload`   |

验证 loader 选择：

```plaintext
静态 avif (brand=avif)      -> vips-loader: heifload
动图 avif (brand=avis)      -> vips-loader: magickload
```

## 默认行为 vs 回退行为

### 正常情况：命中原生 loader（默认只解首帧）

大多数动图格式都能被 libvips 的原生 loader 通过 `is_a()` 认出，`vips_image_new_from_file` 直接选用它们。这些 loader 的 `n`（加载页数）**默认都是 1**，即只解码第一帧：

| loader     | 格式                 | `n` 默认                        |
| ---------- | -------------------- | ------------------------------- |
| `gifload`  | GIF                  | 1                               |
| `webpload` | WebP                 | 1                               |
| `jxlload`  | JPEG-XL              | 1                               |
| `heifload` | HEIC/HEIF/AVIF(静态) | 1                               |
| `pngload`  | PNG                  | 无该选项（libspng，只取默认图） |

实测动画 GIF（108 帧，`gifload`）：`0.04s / 56 MB`，只解首帧，不卡。

### 异常情况：回退到 `magickload`（全序列解码）

AVIF 动图 `is_a()` 失败后，libvips 回退到兜底 loader `magickload`。它的 `n` 默认**同样是 1**，但 ImageMagick 的 `ReadImage` 会**先把整段序列解码进内存**再返回，`n=1` 只限制 libvips 最终包几页，管不住 ImageMagick 内部已解码的全部帧。

实测动画 AVIF（108 帧，`magickload`）：`0.52s / 352 MB`，卡顿与内存升高发生在加载阶段。

> 对比：两者最终都只得到一张 640x360 单帧（`height=360`），差别只在 loader 内部是否把整段动画解码进内存。

## WebP 补丁是否顺带解决了 AVIF（实测：没有）

`patches/libvips-webp-sequential.patch` 只修改 `webpload` 的 `get_flags()`，而 AVIF 走的是 `heifload` 或 `magickload`，因此这个补丁对 AVIF **没有直接影响**。

当前应用已经在 `src/vips/Image.zig` 中对 `.avif` / `.heic` / `.heif` 直接调用 `vips_heifload(..., "n", 1)`，所以「打开 AVIF 动图首帧卡顿」的问题早已被绕开。用 20 帧、640×360、每帧 80ms 的测试 AVIF 复测：

| 方式                             | 未打补丁 libvips          | 打过 WebP 补丁的 libvips |
| -------------------------------- | ------------------------- | ------------------------ |
| `vips heifload ..., --n 1`       | 0.052s                    | 0.062s                   |
| 默认 `vips copy`（`magickload`） | 0.158s                    | 0.178s                   |
| `VIPS_TRACE=1` 的 loader / flags | `heifload` / `SEQUENTIAL` | 同左                     |

补丁前后的差异只是测量噪声；`heifload` 本来就已经声明 `VIPS_FOREIGN_SEQUENTIAL`，瓶颈不在这里。

应用实际加载同一张 AVIF 动图时：

```plaintext
info: Loading image: /tmp/opencode/anim20.avif
info: Image shape: 640x360 (4)
debug: First frame render took 1 ms
```

只显示第一帧，没有进入 `Animation`，也不存在旧版 `magickload` 的加载卡顿。但这也意味着：**补丁没有让 AVIF 动图变得可播放**。

## 修复方向（已实现）

- 按扩展名对 HEIF 家族（`.avif` / `.heic` / `.heif`）统一走 `vips_heifload(..., "n", 1)`。
- 更精确的做法：读取文件头 `ftyp` brand，判断为 `avis` 时走 heifload。

对 HEIF 家族**直接调用原生 `vips_heifload`，绕过 loader 选择，并只取第一帧**，避免回退到 `magickload`。

> 备注：libvips 的 `is_a()` 还有 [`chunk_len > 2048` 就拒绝](https://github.com/libvips/libvips/blob/v8.18.6/libvips/foreign/heifload.c#L420)的保护逻辑（应对 box 超大的 animated AVIF）；但常规 AVIF 动图 ftyp 很小，**brand 不匹配才是根因**。上游主分支至今也未加入 `ftypavis`。

## 补充：为什么动图阶段暂不支持 AVIF

本文前面讨论的是「如何快速拿到 AVIF 动图的第一帧」。这一节讨论的是另一个问题：**为什么动图支持第一阶段不包含 AVIF。**

结论：不是性能取舍，而是**当前 libvips 的 `heifload` 无法枚举 AVIF 动画的帧**，而能枚举的 `magickload` 又不提供逐帧时间信息。

### 1. 原生 `heifload` 只看到 1 页

AVIF 动画（`major_brand = avis`）的帧不是作为多个 top-level image 存放的，而是放在一条 image sequence track 里：

```plaintext
MIME type: image/avif-sequence
main brand: avis
image: 64x64 (id=1), primary
sequence duration: 0.5 seconds
track 1
  handler: 'pict' = image sequence
  sample entry type: av01
```

libvips 的 `heifload` 用 [`heif_context_get_number_of_top_level_images()`](https://github.com/libvips/libvips/blob/v8.18.7/libvips/foreign/heifload.c) 计算页数。对动画 sequence 来说，top-level image 只有主图这一个，所以：

```plaintext
vips heifload anim.avif out.v --n -1
vipsheader -a out.v
  n-pages: 1
  vips-loader: heifload
```

此时 `n-pages` 为 1，容器拿不到真实帧数。尝试按页读取也会直接失败：

```plaintext
vips heifload anim.avif out.v --page 1 --n 1
  heifload: bad page number
```

所以 `page` / `n` 两个参数对 AVIF 动画没有意义，无法支撑「按帧迭代 + 缓存」的容器。

### 2. `magickload` 能看到 5 帧，但没有时间信息

回退到 ImageMagick 后确实能拿到帧数：

```plaintext
vipsheader -a anim.avif
  n-pages: 5
  vips-loader: magickload
  format: ushort
```

但它的元数据里**没有 `delay`、`loop`、`page-height`**，只有 `n-pages` 和 `magick-format`。也就是说：

- 能知道有几帧；
- 但拿不到每帧显示时长，无法计算 PTS；
- 而且 ImageMagick 会在加载阶段把整段动画解码进内存，正是本文前面实测到的 `0.52s / 352MB` 行为（108 帧样本）。

即便只是为了拿到帧数而接受一次全量解码，后续播放仍然缺少帧时长，无法做真正的动图播放。

### 3. 其他次要因素

- 12-bit / 16-bit 的 AVIF（`format: ushort`）每一帧都要经过 `toSrgb()` 转成 UChar，逐帧成本高于 GIF/WebP。
- 动画 AVIF 的帧尺寸、alpha、色彩空间在不同编码器下差异较大，需要额外的兼容性验证。

### 4. libheif 1.23.5 的 sequence track API 已验证

「暂不支持」的直接原因是 **libvips 的 `heifload` 只枚举 top-level image**，并不是 libheif 没有能力读动画。当前 Nix 环境中的 libvips 8.18.7 链接的是 libheif 1.23.5，它已经提供完整的 sequence track API：

- `heif_context_has_sequence()`
- `heif_context_get_sequence_timescale()`
- `heif_context_number_of_sequence_tracks()`
- `heif_context_get_track_ids()` / `heif_context_get_track()`
- `heif_track_decode_next_image()`
- `heif_image_get_duration()`

用上面那张 20 帧 AVIF 写了一个最小 C 程序验证：

```plaintext
has_sequence=1 seq_timescale=125 tracks=2
track 1 handler=pict timescale=125 reps=4294967295
  resolution=640x360
  frame 0 duration=10 ticks
  frame 1 duration=10 ticks
  ...
  frame 19 duration=10 ticks
  decoded=20 total=1.600 s
track 2 handler=auxv timescale=125 reps=4294967295
```

`10 / 125 = 80ms`，与实际编码参数一致；20 帧累计 1.6s。track 2 是 alpha 辅助轨，真正实现时需要和主 `pict` 轨一起处理。`seq_duration` 在无限循环时会返回 `UINT64_MAX`，不能直接使用，必须累加每帧的 `heif_image_get_duration()`。

因此，AVIF 动图**不是技术上不可行**，而是需要绕过 libvips，直接用 libheif 做一个新的容器：

1. 打开 context，检测 `has_sequence`，取 `pict` 轨和 alpha `auxv` 轨。
2. 用 `heif_track_decode_next_image()` 顺序解码，读取每帧 duration，换算成毫秒并累计 PTS。
3. 合成 alpha、做 sRGB 转换，再复用现有 GPU 纹理更新和缓存设计。

这会是一套独立于 `src/vips/Animation.zig` 的实现，工作量明显大于 GIF/WebP，因此仍不放进当前阶段。

### 5. 现阶段的处理方式

- 动图支持 **GIF + WebP + JXL**：这三者的 `n-pages`、`delay`（毫秒）、`loop` 都能从 libvips 原生 loader 直接取得。
- AVIF/HEIC 继续维持现状：只加载第一帧，作为静态图片显示。
- WebP sequential 补丁只改善 WebP；`Animation.openRoll()` 的 `access=sequential` 同时覆盖 GIF/WebP/JXL。两者都不会改变 AVIF 的 loader 选择或播放能力。
- 后续若要支持 AVIF 动图，首选路线是直接集成 libheif 的 sequence track API（已验证可行）；其次才是等 libvips `heifload` 上游支持 sequence track。
