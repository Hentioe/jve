// 编号 7：热成像
// 把画面亮度当作温度，映射到经典的黑体 / 铁红调色板：
// 冷区是深蓝紫，热区依次经过红、橙、黄，最热处接近白色。
// 采样时做了轻微模糊和传感器噪声，模拟普通热像仪的观感。

[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

static const float3 LUMINANCE_WEIGHTS = float3(0.2126f, 0.7152f, 0.0722f);

float hash21(float2 p)
{
    return frac(sin(dot(p, float2(12.9898f, 78.233f))) * 43758.5453f);
}

float3 ironbow(float t)
{
    t = saturate(t);

    float3 c0 = float3(0.02f, 0.00f, 0.07f); // 冷：近黑紫
    float3 c1 = float3(0.10f, 0.00f, 0.30f); // 深紫
    float3 c2 = float3(0.40f, 0.00f, 0.55f); // 蓝紫
    float3 c3 = float3(0.75f, 0.02f, 0.40f); // 洋红
    float3 c4 = float3(1.00f, 0.15f, 0.10f); // 红
    float3 c5 = float3(1.00f, 0.45f, 0.00f); // 橙
    float3 c6 = float3(1.00f, 0.80f, 0.00f); // 黄
    float3 c7 = float3(1.00f, 0.95f, 0.25f); // 亮黄
    float3 c8 = float3(1.00f, 1.00f, 1.00f); // 白热

    float3 col = lerp(c0, c1, smoothstep(0.00f, 0.12f, t));
    col = lerp(col, c2, smoothstep(0.12f, 0.28f, t));
    col = lerp(col, c3, smoothstep(0.28f, 0.42f, t));
    col = lerp(col, c4, smoothstep(0.42f, 0.55f, t));
    col = lerp(col, c5, smoothstep(0.55f, 0.68f, t));
    col = lerp(col, c6, smoothstep(0.68f, 0.80f, t));
    col = lerp(col, c7, smoothstep(0.80f, 0.90f, t));
    col = lerp(col, c8, smoothstep(0.90f, 1.00f, t));
    return col;
}

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
    float2 uv = saturate(input.UV);
    float2 texel = float2(
        max(abs(ddx(uv.x)), 1e-6f),
        max(abs(ddy(uv.y)), 1e-6f)) * 1.5f;

    // 5 点轻微模糊，模拟热像仪偏软的低分辨率镜头
    float4 c = g_BackgroundTex.Sample(uv) * 0.40f;
    c += g_BackgroundTex.Sample(saturate(uv + float2( texel.x, 0.0f))) * 0.15f;
    c += g_BackgroundTex.Sample(saturate(uv + float2(-texel.x, 0.0f))) * 0.15f;
    c += g_BackgroundTex.Sample(saturate(uv + float2(0.0f,  texel.y))) * 0.15f;
    c += g_BackgroundTex.Sample(saturate(uv + float2(0.0f, -texel.y))) * 0.15f;

    float alpha = c.a;
    float3 base = c.rgb / max(c.a, 1e-4f);
    float temp = dot(base, LUMINANCE_WEIGHTS);

    // 传感器噪声 + 轻微的暗部提升，让冷区不是死黑
    float noise = (hash21(floor(uv * float2(1024.0f, 1024.0f))) - 0.5f) * 0.018f;
    temp = saturate(pow(saturate(temp), 0.88f) + noise + 0.015f);

    float3 rgb = ironbow(temp);

    // 热区加一点暖色辉光
    float hot = smoothstep(0.72f, 1.0f, temp);
    rgb += float3(1.0f, 0.55f, 0.08f) * hot * 0.10f;

    // 轻微暗角，像镜头边缘的温度衰减
    float2 p = uv - 0.5f;
    rgb *= 1.0f - 0.22f * smoothstep(0.35f, 0.75f, length(p));

    return float4(saturate(rgb) * alpha, alpha);
}
