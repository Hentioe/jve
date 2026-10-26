// 简单的水面倒影模拟（用于测试点击位置参数）
[[vk::binding(0, 2)]]
Sampler2D image;

static const float WATER_LEVEL = 0.70;
static const float TRANSITION  = 0.04;

// 多频横向位移：连续、有节奏、不碎
// (x, depth) → 横向偏移；depth 让相位往下推进 → 看起来像水里漂
float waveX(float x, float depth)
{
    float wx = 0.0;
    wx += sin(x *  9.0 + depth *  35.0)            * 0.0085;
    wx += sin(x * 19.0 + depth *  70.0 + 1.3)      * 0.0050;
    wx += sin(x * 37.0 + depth * 120.0 + 2.7)      * 0.0025;
    return wx;   // 峰值 ≈ 0.016
}

[shader("fragment")]
float4 main(float2 uv : TEXCOORD0) : SV_Target
{
    float4 s   = image.SampleLevel(uv, 0.0);
    float3 src = s.rgb;

    float depth = uv.y - WATER_LEVEL;
    if (depth < 0.0)
        return float4(src, s.a);

    float dn = depth / (1.0 - WATER_LEVEL);

    // ---------- 镜像源 + 纵向拉丝（结构保留的关键） ----------
    float base_y  = WATER_LEVEL - depth;
    float stretch = 0.003 + 0.015 * dn;     // 9-tap 纵向拉伸
    float dispAmp = 0.7 + 0.5 * dn;         // 深处位移略大

    float3 refl = 0.0;
    float  wsum = 0.0;
    const int TAPS = 9;
    for (int k = 0; k < TAPS; k++)
    {
        float tk = (float(k) / float(TAPS - 1)) * 2.0 - 1.0;
        float w  = exp(-tk * tk * 2.0);
        float py = base_y + tk * stretch;
        // 每个 tap 的横向位移 = waveX(x, py) —— 用 py 而不是 depth
        // 同一列相邻 tap 的 py 差仅 stretch ≈ 0.01，sin 相位差极小 → 平滑拖影，不碎
        float wx = waveX(uv.x, py) * dispAmp;
        float px = clamp(uv.x + wx, 0.0, 1.0);
        refl += image.SampleLevel(float2(px, clamp(py, 0.0, 1.0)), 0.0).rgb * w;
        wsum += w;
    }
    refl /= wsum;

    // ---------- 颜色：乘法暗化 + 冷调 + 去饱和 ----------
    float3 col = refl * (0.80 - 0.14 * dn);            // 0.80 → 0.66
    col *= float3(0.93, 0.97, 1.02);                   // 轻微冷
    float luma = dot(col, float3(0.299, 0.587, 0.114));
    col = lerp(col, float3(luma), 0.12 + 0.10 * dn);   // 12% → 22%

    // ---------- 水面亮线（平滑高斯，无白点） ----------
    float lineMask = exp(-pow((depth - 0.004) / 0.006, 2.0));
    col += lineMask * 0.08 * float3(1.0, 0.97, 0.92);

    // ---------- 过渡带 ----------
    if (depth < TRANSITION)
    {
        float r = depth / TRANSITION;
        float t = r * r * (3.0 - 2.0 * r);
        col = lerp(src, col, t);
    }

    return float4(saturate(col), s.a);
}
