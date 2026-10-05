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

## 修复方向（已实现）

- 按扩展名对 HEIF 家族（`.avif` / `.heic` / `.heif`）统一走 `vips_heifload(..., "n", 1)`。
- 更精确的做法：读取文件头 `ftyp` brand，判断为 `avis` 时走 heifload。

对 HEIF 家族**直接调用原生 `vips_heifload`，绕过 loader 选择，并只取第一帧**，避免回退到 `magickload`。

> 备注：libvips 的 `is_a()` 还有 [`chunk_len > 2048` 就拒绝](https://github.com/libvips/libvips/blob/v8.18.6/libvips/foreign/heifload.c#L420)的保护逻辑（应对 box 超大的 animated AVIF）；但常规 AVIF 动图 ftyp 很小，**brand 不匹配才是根因**。上游主分支至今也未加入 `ftypavis`。
