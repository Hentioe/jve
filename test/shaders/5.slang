// 编号 5：点阵字符画
// 把画面切成小格子，每个格子按亮度选择一个 5x5 的点阵符号，
// 再用格子本身的颜色给符号上色，形成类似十字绣 / 字符画的效果。

[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

static const float3 LUMINANCE_WEIGHTS = float3(0.2126f, 0.7152f, 0.0722f);

// 7 级密度：空、点、冒号、加号、叉、井号、实心块
// 每个符号用 5 行、每行 5 个 bit 表示（bit0 在最左边）
static const uint GLYPHS[35] = {
    0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x04, 0x00, 0x00,
    0x00, 0x04, 0x00, 0x04, 0x00,
    0x00, 0x04, 0x0E, 0x04, 0x00,
    0x11, 0x0A, 0x04, 0x0A, 0x11,
    0x0A, 0x1F, 0x0A, 0x1F, 0x0A,
    0x1F, 0x1F, 0x1F, 0x1F, 0x1F,
};

float2 aspect_scale(float2 uv)
{
    float dx = max(abs(ddx(uv.x)), 1e-6f);
    float dy = max(abs(ddy(uv.y)), 1e-6f);
    float aspect = clamp(dy / dx, 0.1f, 10.0f);
    return (aspect >= 1.0f) ? float2(aspect, 1.0f)
                           : float2(1.0f, 1.0f / aspect);
}

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
    float2 uv = saturate(input.UV);
    float2 scale = aspect_scale(uv);

    // 横向固定 64 个字符格，纵向按宽高比换算，保证格子是正方形
    float aspect = scale.x / scale.y;
    float2 grid = float2(64.0f, max(8.0f, 64.0f / aspect));

    float2 cell = floor(uv * grid);
    float2 cell_center = (cell + 0.5f) / grid;

    // 采样格子中心的颜色与 Alpha
    float4 src = g_BackgroundTex.Sample(cell_center);
    float alpha = src.a;
    float3 base = src.rgb / max(src.a, 1e-4f);

    float luma = saturate(dot(base, LUMINANCE_WEIGHTS));
    int level = clamp(int(luma * 7.0f), 0, 6);

    // 格子内部的 5x5 点阵坐标
    float2 local = frac(uv * grid);
    int2 pix = clamp(int2(floor(local * 5.0f)), int2(0, 0), int2(4, 4));

    uint bits = GLYPHS[level * 5 + pix.y];
    bool on = ((bits >> pix.x) & 1u) != 0u;

    // 暗色底 + 带一点全息感的彩色符号
    float3 bg = float3(0.008f, 0.010f, 0.016f) * alpha;
    float3 ink = lerp(base, float3(0.72f, 0.88f, 1.0f), 0.10f);
    ink *= 0.60f + 0.65f * luma;

    float3 rgb = on ? saturate(ink) * alpha : bg;
    return float4(rgb, alpha);
}
