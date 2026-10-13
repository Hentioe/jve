# Slang 着色器迁移说明

把内建着色器从 HLSL（dxc / SDL_shadercross）迁移到 [Slang](https://shader-slang.org/)。

- 新源文件：`src/shaders/*.slang`（构建实际使用的）。
- 旧文件：`src/shaders/*.hlsl` 保留作参考，但不再参与构建。
- 编译器：`slangc`，产物仍是 SPIR-V，供 SDL_GPU 直接加载。

## 1. 编译命令简化

`build.zig` 里每条着色器编译命令只剩：

```bash
slangc <input.slang> -o <output.spv>
```

原因：

| 参数                     | 为什么不写                                                          |
| ------------------------ | ------------------------------------------------------------------- |
| `-target spirv`          | 由输出文件的 `.spv` 扩展名推断                                      |
| `-stage vertex/fragment` | 由源文件里的 `[shader("vertex")]` / `[shader("fragment")]` 属性推断 |
| `-entry main`            | 默认入口就是 `main`                                                 |

对应地，每个着色器的入口函数都带上了阶段属性，例如：

```slang
[shader("fragment")]
float4 main(...) : SV_Target { ... }
```

## 2. 绑定：从 `space/register` 到 `[[vk::binding]]`

dxc 时代写的是 D3D 语义：

```hlsl
cbuffer BaseUniforms : register(b0, space3) { ... };
Texture2D Texture : register(t0, space2);
```

Slang 推荐直接写 Vulkan 语义，不再依赖 `register`：

```slang
[[vk::binding(0, 3)]]
cbuffer BaseUniforms { ... };

[[vk::binding(0, 2)]] Texture2D Texture;
[[vk::binding(0, 2)]] SamplerState Sampler;
```

`[[vk::binding(binding, set)]]`：**第一个数字是 binding，第二个数字是 set**。

它与旧写法的等价关系是：

```text
register(xN, spaceS)  ==>  set = S, binding = N
```

所以 `b0, space3` → `[[vk::binding(0, 3)]]`；`t1, space2` → `[[vk::binding(1, 2)]]`。
这样一来“数字有点懵”其实只是：`register` 的序号变成 binding，`space` 变成 set。

### 本项目的 set 约定

这些 set 编号沿用迁移前 dxc 的 `space`，SDL_GPU 通过 SPIR-V 反射识别。

| set | 用途                                          |
| --- | --------------------------------------------- |
| 1   | marker 顶点着色器的 uniform                   |
| 2   | 纹理与采样器（binding = 原来 `t`/`s` 的序号） |
| 3   | 片段着色器的 uniform                          |

各着色器实际绑定：

| 着色器          | set 1              | set 2                                                                        | set 3                |
| --------------- | ------------------ | ---------------------------------------------------------------------------- | -------------------- |
| `base.vert`     |                    |                                                                              |                      |
| `checker.vert`  |                    |                                                                              |                      |
| `base.frag`     |                    | `Texture`=0, `Sampler`=0                                                     | `BaseUniforms`=0     |
| `blur.frag`     |                    | `g_InputTexture`=0, `g_LinearSampler`=0                                      | `BlurUniforms`=0     |
| `sharpen.frag`  |                    | `inputTexture`=0, `inputSampler`=0                                           | `SharpenUniforms`=0  |
| `fog.frag`      |                    |                                                                              | `FogUniforms`=0      |
| `overflow.frag` |                    |                                                                              | `OverflowUniforms`=0 |
| `checker.frag`  |                    |                                                                              |                      |
| `welcome.frag`  |                    |                                                                              |                      |
| `marker.vert`   | `MarkerUniforms`=0 |                                                                              |                      |
| `marker.frag`   |                    |                                                                              | `MarkerUniforms`=0   |
| `mask.frag`     |                    | `u_MainTexture`=0 / `u_MainSampler`=0，`u_MaskTexture`=1 / `u_MaskSampler`=1 |                      |
| `onscreen.frag` |                    | `Texture`=0, `Sampler`=0                                                     |                      |
| `text.frag`     |                    | `Texture`=0, `Sampler`=0                                                     | `TextUniforms`=0     |

## 3. SDL_GPU 的纹理 + 采样器必须共享同一个 binding（重点）

SDL_GPU 在运行时把「纹理 + 采样器」当作**一个组合绑定**（`SDL_GPUTextureSamplerBinding`）。
因此 Slang 里必须把两者声明在**同一个 `(set, binding)`** 上：

```slang
[[vk::binding(0, 2)]] Texture2D Texture;
[[vk::binding(0, 2)]] SamplerState Sampler;   // 与 Texture 同一个 0, 2
```

`mask.frag` 需要两张纹理，就写成 binding 0 与 1 两对：

```slang
[[vk::binding(0, 2)]] Texture2D u_MainTexture;
[[vk::binding(0, 2)]] SamplerState u_MainSampler;

[[vk::binding(1, 2)]] Texture2D u_MaskTexture;
[[vk::binding(1, 2)]] SamplerState u_MaskSampler;
```

纹理的 binding 从 0 连续递增，与 CPU 侧 `SDL_BindGPUFragmentSamplers(..., first_slot, ...)`
的顺序一一对应。

> 说明：也可以改用 Slang 的合并类型 `Sampler2D`（它只占一个 binding），但那会生成
> combined image sampler；本项目沿用“独立 image + 独立 sampler、同 binding”的形式，
> 以与迁移前 dxc 产出的 SPIR-V 保持一致。

## 4. 需要屏蔽的警告：E39001

纹理与采样器必须共享同一个 `(set, binding)`（第 3 节 SDL_GPU 的要求），而 Slang 会把
同号绑定判为“绑定重叠”并报 `E39001`（dxc 对 `t`/`s` 同号并不告警）。这对 SDL_GPU 而言
是**预期且必须**的，所以在文件里说明理由后局部屏蔽：

```slang
// 说明为什么这是有意的，然后：
#pragma warning(disable: 39001)
```

目前 `base.frag`、`blur.frag`、`sharpen.frag`、`mask.frag`、`onscreen.frag`、`text.frag`
这 6 个含纹理的着色器都带这一行。

## 5. cbuffer 布局：Slang 使用 std140

Slang 面向 Vulkan 对 cbuffer 使用 **std140** 布局（例如 `float2` 需要 8 字节对齐）。
迁移前 dxc 的打包规则与之不同，所以 CPU 侧与着色器 cbuffer 对应的 `extern struct`
也必须按 std140 对齐——在 `src/display/structs.zig` 里用显式 padding 表达。

规则：**着色器的参数是唯一事实来源**，Zig 结构体只保留着色器真正读取的成员，
补位仅在 std140 强制对齐处保留。例如 `SharpenUniforms`：

```zig
pub const SharpenUniforms = extern struct {
    strength: f32,
    _align: f32 = 0.0, // std140：float2 需要 8 字节对齐
    texture_size: [2]f32,
};
```

当前各 cbuffer 的 std140 布局（与 `structs.zig` 一一对应）：

| 着色器          | 成员偏移       | block 大小 |
| --------------- | -------------- | ---------- |
| `base.frag`     | 0,4,8,12,16,20 | 24         |
| `blur.frag`     | 0,8,16         | 20         |
| `fog.frag`      | 0              | 4          |
| `marker.vert`   | 0              | 8          |
| `marker.frag`   | 0,4            | 8          |
| `overflow.frag` | 0,4,8          | 12         |
| `sharpen.frag`  | 0,8            | 16         |
| `text.frag`     | 0,16           | 20         |

改动着色器参数（增删成员或顺序）时，务必同步更新 `structs.zig`，可用
`spirv-cross <shader>.spv --reflect` 对照偏移与 block 大小。
