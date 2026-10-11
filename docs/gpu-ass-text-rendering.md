# 在 GPU 上渲染 ASS 文字

## 结论

libass 负责把文字**栅格化**成一张（或多张）带透明度的位图；GPU 侧只做三件事：

1. 把位图上传成纹理；
2. 用位图尺寸构造一个**按显式位置定位**的 quad；
3. 用一条专用管线采样覆盖率，叠加到全屏效果之上。

这样就不再受"所有内容都全屏渲染"的限制：文字是一块独立的小 quad，位置完全由顶点决定。

职责分层：`Text.zig` 负责栅格化（可选墨迹裁剪），产出一个与 libass 解耦的 `Rendered`
纯数据；`TextPipeline.zig` 只消费该数据，负责上传、建 quad、采样与绘制，不接触 `ass.Image`。

## 数据来源：ASS_Image

栅格化结果是 `ASS_Image` 链表，每个节点包含：

| 字段      | 含义                                             |
| --------- | ------------------------------------------------ |
| `w`, `h`  | 位图宽高（像素）                                 |
| `stride`  | 每行字节数，可能大于 `w`；**最后一行不保证补齐** |
| `bitmap`  | **每像素 1 字节**的覆盖率（灰度），不是 RGBA     |
| `color`   | 该节点的颜色（含 alpha），按 RGBA 字节序         |
| `dst_x/y` | libass 建议的摆放位置（帧左上角为原点）          |
| `next`    | 下一个节点，没有则为空                           |

## GPU 渲染流程

### 1. 位图 → 纹理

bitmap 是单通道覆盖率，先展开成 RGBA8888 再走现有 `Uploader.uploadTexture`（它按 4 字节/像素处理）。逐行拷贝时用 `stride` 取源行，忽略行尾填充。

### 2. 尺寸 + 位置 → 顶点

用裁剪后的位图尺寸结合显式位置构造 6 个顶点（两个三角形）覆盖目标矩形，UV 取 0..1，
复用 `base.vert`（输出 `pos` + `uv`）。位置为文字 quad **左上角在帧内的像素坐标**
（原点为帧左上角），默认 `(0, 0)`（左上角）。居中不再隐式发生，需要时用
`TextPipeline.Options.centered(...)` 显式计算。

### 3. 颜色 → uniform

颜色作为片元 uniform 传入，纹理只存覆盖率。片元着色器：

```hlsl
float coverage = Texture.Sample(Sampler, uv).r;
return float4(u_Color.rgb, coverage * u_Color.a);
```

管线已开启 alpha 混合（`SRC_ALPHA / ONE_MINUS_SRC_ALPHA`），所以会自动叠加到下方内容。
uniform 里另有一个 `debug` 字段：为 true 时把红色作为四边形的**不透明底色**，
文字按其真实 alpha 叠在红底上，便于观察 quad 的位置与大小，同时不丢失透明度。

### 4. 每帧叠加

同一个 render pass 内：先画全屏日食，再绑定文字管线 + 文字顶点缓冲 + 采样器，推送颜色 uniform，`Draw` 6 个顶点。

## 位置与居中

### 位置显式传递

`TextPipeline.Options.position` 指定文字 quad 左上角的像素坐标（帧左上角为原点），
默认 `(0, 0)` 即左上角。居中只是其中一种摆放方式，由调用方显式计算：

```plaintext
x0 = (frame_w - tex_w) / 2
y0 = (frame_h - tex_h) / 2
```

`TextPipeline.Options.centered(raster_width, raster_height, frame_size)` 提供了这个便捷构造。

### 像素 → NDC

```plaintext
ndc_x = px / frame_w * 2 - 1
ndc_y = 1 - py / frame_h * 2     // 注意 Y 轴翻转
```

### 不要直接用 dst_x / dst_y

libass 居中时会把**最后一个字后面的 Spacing 也算进总宽**，导致字形重心向左偏 `Spacing/2`。

实测（`PlayRes=1024x768`，`Spacing=80`，"JVE"）：字形中心落在 `472`，而帧中心是 `512`，正好左偏 40 = `Spacing/2`。

因此不使用 libass 建议的 `dst_x/dst_y`，而是由调用方基于（可选的）墨迹裁剪尺寸自行定位。

## 裁剪到墨迹包围盒（可选）

### 为什么：libass 光栅化器的固定 padding（主因是 tile 对齐）

右侧（和底部）的透明留白**不是**文字或图形自身造成的，而是 libass 光栅化每个
glyph 位图时主动加的 padding。分两步（libass 0.17.4）：

**1. tile 尺寸决定了对齐粒度** —— `ass_bitmap_engine.c`：

```c
engine.tile_order = mask & ASS_FLAG_LARGE_TILES ? 5 : 4;  // 1<<4 = 16px（large tiles 为 32px）
```

**2. 位图宽高按 tile 向上取整** —— `ass_bitmap.c` 的 `ass_outline_to_bitmap()`：

```c
// enlarge by 1/64th of pixel to bypass slow rasterizer path, add 1 pixel for shift_bitmap
int32_t x_min = (rst->bbox.x_min -   1) >> 6;   // 左侧约 -1px
int32_t x_max = (rst->bbox.x_max + 127) >> 6;   // 右侧比左侧多 128/64 = 2px
int32_t w = x_max - x_min;
int mask = (1 << render_priv->engine.tile_order) - 1;   // 15（large tiles 为 31）
int32_t tile_w = (w + mask) & ~mask;                    // ★ 向上取整到 16 的倍数
ass_alloc_bitmap(..., bm, tile_w, tile_h, ...);         // bm->w = tile_w（含空白）
bm->left = x_min; bm->top = y_min;
```

随后：

- `ass_render.c` 的 `render_glyph()` 直接把 `bm->w` 当作 `ASS_Image.w`
  （`b_x1 = bm->w`），padding 进入结果；
- 合成单张位图时，`ass_composite_construct()` 又原样拷贝
  （`if (!bord && n_bm == 1) ass_copy_bitmap(...)`），于是这些透明列被完整保留。

所以留白的**主因是 `tile_w` 的向上对齐**（右侧最多可多出 `tile_size - 1` =
**15px**，large tiles 为 **31px**），`+127` 的 2px 只是零头；而左侧只由 `-1` 决定、
约 1px，故左右明显不对称。该 padding 对文字、`\p1` 矢量图形、图标一视同仁。

#### 数值示例

帧 1024×768，PlayRes 默认 384×288 → `screen_scale_x = 1024/384 = 2.667`。
用 `{\p1}m 0 0 l 200 0 l 200 2 l 0 2{\p0}`，矩形 x∈[0,200] → 设备像素约 [0, 533.33]：

| 量       | 值                               |
| -------- | -------------------------------- |
| `x_min`  | `(0 - 1) >> 6 = -1` → 左留 ~1px  |
| `x_max`  | `(533.33 × 64 + 127) >> 6 = 535` |
| `w`      | 535 − (−1) = 536                 |
| `tile_w` | `(536 + 15) & ~15 = 544`         |
| 右留白   | ≈ 544 − 534 ≈ **10px**           |

即肉眼看到的右侧约 10px，远大于 2px——多出的正是 tile 对齐余量。

> 结论：所谓“留白”是 **libass 光栅化的内边距 + tile 对齐**，不是字体 side bearing，
> 也与 `Spacing` 无关。实测同一个 `"JVE"`（FontSize 28）`ASS_Image.w` 随 Spacing 增大
> 只多出字间空隙（差值 `2 × 80`），末尾那点空白即来自光栅化 padding。因此
> `Text.Options.trim`（墨迹裁剪）对**文字**必要；而**图标**可以改走“适配画布”路线
> 从根本上规避（见下一节）。

### 怎么做

`Text.Options.trim`（默认 `true`）控制是否裁剪。开启时扫描位图，求出**覆盖率非零的
最小矩形**（墨迹包围盒），纹理只保留该矩形区域；关闭时使用整幅位图。

该逻辑封装在 `src/ui/helper.zig` 的 `imageInkBounds()`：逐行按
`stride` 扫描（最后一行不保证补齐），返回 `{x, y, w, h}`；全透明时返回 `null`，调用处回退整幅。

## 图标：适配画布，免裁剪

文字宽度取决于内容、无法预知，所以要用墨迹裁剪去掉 libass 的 tile padding。
图标不一样——它是我们自己按固定的正方形画布设计的矢量图形，可以把 padding
直接“挤出”画布，从而**不再需要 trim**。

做法（见 `src/ui/Icon.zig` / `src/ui/IconRenderer.zig` / `src/ui/icons.zig`）：

1. **固定绘制坐标空间** `PLAY_RES = 320`，图标路径按 `0..320` 书写。
2. **左上角锚定**：每条图标用 `\an7\pos(0,0)` 把绘制原点锚到画布左上角，
   让 `0..PLAY_RES` 与画布一一对应（否则 libass 对 `\p` 图形的“基线/对齐”
   行为不可靠，会偏位）。
3. **让 frame 等于输出边长**：渲染前 `setFrameSize(BASE_SIZE * scale)`（默认
   32），PlayRes 保持 320。libass 会按 `frame / PLAY_RES = 0.1` 把绘制坐标缩放
   到输出。
4. **直接返回整幅画布**：图形铺满整幅画布，libass 光栅化时按 tile 对齐、左右
   补的 padding 全部落在画布外被 frame 裁掉；画布内没有墨迹的地方就是单元格
   里预期的透明留白。于是纹理尺寸恒为 `frame × frame`。
5. **图标只描述几何，不含颜色**：路径里不写 `\1c`/`\3c`。颜色由外部
   `Icon.Options.color`（ASS 颜色，见下节）直接写入 `style.PrimaryColour` /
   `OutlineColour`，libass 原样透传到 `AssRendered.color` 交给着色器 uniform。
   因此同一个图标可被外部任意改色（限制：整图标单色）。

对比旧实现为什么需要 trim：旧代码用 `frame = 320` 而图形只有约 32px，小位图
被上面第 2 步的 `tile_w = (w + 15) & ~15` 撑到 `47×47`（stride 48），多出的透明
列只能靠 trim 削掉。把 frame 缩到与图形同量级后，位图本身即等于画布，padding
无处可放。

### 图形设计注意：描边会随 PlayRes 缩放

图标路径的单位是 `PLAY_RES`（320），渲染时整体乘以 `frame / PLAY_RES = 0.1`。
**描边/边框也会按同样比例缩放**：`\bord2` 实际只有 `2 × 0.1 = 0.2px`，覆盖率约
20%，看起来又淡又偏色（叠加 debug 的红色更明显），但它的颜色其实是对的——
只是太细。因此图标里的实心笔画应尽量用 `\p1` 的**填充**（`\bord0` + 填充几何，
`close` / `image` / `minimize` 均已如此），或把描边数值按比例放大（想要 2px 就写
`\bord20`）。

### 合成：遍历 ASS_Image 链表

libass 对每个 event 只光栅化**墨迹的紧致矩形**，真实位置放在 `dst_x` / `dst_y`；
描边与填充还会拆成多个节点。只取链表头会丢掉位置（图标贴角）和其中一层颜色。
`src/ui/helper.zig` 的 `compose()` 遍历整条 `ASS_Image` 链，把每层按 `dst_x/dst_y`
合成到一整幅 `frame × frame` 画布上（覆盖率取各层最大值），因此 `\pos` / 对齐
都被保留。

### 颜色表示

`.color` 是一枚 u32，**沿用 ASS 自己的颜色表示**（也就是 `ASS_Style.PrimaryColour`
与 `ASS_Image.color` 的格式），不另造一套：

```plaintext
0xRRGGBBAA        R/G/B 为高 24 位，低字节是 ASS alpha：0x00 = 不透明，0xFF = 全透明
```

因此它可以**直接**赋给 `style.PrimaryColour`，也能**直接**从 `ASS_Image.color` 读回，
两者之间没有任何转换。不透明白 = `0xFFFFFF00`（`Icon.Options.color` /
`Text.Options.color` 的默认值）。

`TextUniforms.fromColor()` 把它解成着色器用的归一化 RGBA：
`r=>>24, g=>>16, b=>>8, a=255-低字节`。

> 若将来需要更直观的表示（例如拆成 `r/g/b/a` 四个分量），应新增独立的字段，
> 而不是把单个 u32 解释成另一套格式。

## 两个已知坑

### Alignment 是位掩码，不是小键盘值

`ASS_Style.Alignment` 使用 `VALIGN_* | HALIGN_*`。小键盘 5（居中）对应的是
`VALIGN_CENTER(8) | HALIGN_CENTER(2)`；直接写 `5` 会被解释成"靠左"。

### PlayRes 未设时 libass 假定 384x288

此时 `FontSize`、`Spacing` 等脚本单位会按 `帧尺寸 / 384`（本窗口约 2.67 倍）缩放。
若希望"单位 = 帧像素"，应设 `PlayResX/Y = 帧尺寸`，并把字号按比例放大
（例如 `28 × 1024/384 ≈ 75`）；否则保持不设、接受缩放即可。

## 相关文件

| 文件                           | 职责                                                    |
| ------------------------------ | ------------------------------------------------------- |
| `src/ass/*`                    | libass 封装（Library / Renderer）                       |
| `src/ui/Text.zig`              | 文字栅格化（可选墨迹裁剪）→ 与 libass 解耦的 `Rendered` |
| `src/ui/Icon.zig`              | 图标栅格化（适配画布、免裁剪、合成整条图层链）          |
| `src/ui/IconRenderer.zig`      | 图标专用 renderer（固定 PlayRes，frame = 输出边长）     |
| `src/ui/helper.zig`            | `compose()` 图层合成                                    |
| `src/ui/AssRendered.zig`       | 与 libass 解耦的栅格化结果（覆盖率 + 尺寸 + 颜色）      |
| `src/display/TextPipeline.zig` | 上传覆盖率纹理、按位置构造 quad、建立并绘制文字管线     |
| `src/shaders/text.frag.hlsl`   | 采样覆盖率 × 颜色                                       |
| `src/display/structs.zig`      | `TextUniforms`（颜色 uniform / `fromColor`）            |

## 扩展

- **图标**（`src/ui/Icon.zig`）：已用 `compose()` 遍历整条 `ASS_Image` 链并合成，
  能处理多节点（描边 / 填充）。
- **文字**（`src/ui/Text.zig`）：当前仍只处理**单个** `ASS_Image` 节点。若出现多
  节点（多颜色 / 描边 / 阴影），需要按 `compose()` 的方式遍历链表合成后再上传。
