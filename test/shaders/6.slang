// 编号 6：霓虹描边（Neon Edge）
// 用 Sobel 算子提取亮度边缘，把原图压暗后叠上青蓝到洋红的霓虹渐变。
// 适合测试周围像素采样、透明图片的轮廓以及预乘 Alpha 的处理。

[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

static const float3 LUMINANCE_WEIGHTS = float3(0.2126f, 0.7152f, 0.0722f);

float2 aspect_scale(float2 uv)
{
    float dx = max(abs(ddx(uv.x)), 1e-6f);
    float dy = max(abs(ddy(uv.y)), 1e-6f);
    float aspect = clamp(dy / dx, 0.1f, 10.0f);
    return (aspect >= 1.0f) ? float2(aspect, 1.0f)
                           : float2(1.0f, 1.0f / aspect);
}

float luma_of(float4 c)
{
    return dot(c.rgb, LUMINANCE_WEIGHTS);
}

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
    float2 uv = saturate(input.UV);
    // 一个像素对应的 UV 步长，直接由屏幕导数得到，无需额外 uniform
    float2 texel = float2(
        max(abs(ddx(uv.x)), 1e-6f),
        max(abs(ddy(uv.y)), 1e-6f));

    float2 o = texel;

    // 3x3 Sobel 亮度梯度
    float tl = luma_of(g_BackgroundTex.Sample(saturate(uv + float2(-o.x, -o.y))));
    float tc = luma_of(g_BackgroundTex.Sample(saturate(uv + float2( 0.0f, -o.y))));
    float tr = luma_of(g_BackgroundTex.Sample(saturate(uv + float2( o.x, -o.y))));
    float ml = luma_of(g_BackgroundTex.Sample(saturate(uv + float2(-o.x,  0.0f))));
    float mr = luma_of(g_BackgroundTex.Sample(saturate(uv + float2( o.x,  0.0f))));
    float bl = luma_of(g_BackgroundTex.Sample(saturate(uv + float2(-o.x,  o.y))));
    float bc = luma_of(g_BackgroundTex.Sample(saturate(uv + float2( 0.0f,  o.y))));
    float br = luma_of(g_BackgroundTex.Sample(saturate(uv + float2( o.x,  o.y))));

    float gx = (tr + 2.0f * mr + br) - (tl + 2.0f * ml + bl);
    float gy = (bl + 2.0f * bc + br) - (tl + 2.0f * tc + tr);
    float edge = length(float2(gx, gy));

    float4 center = g_BackgroundTex.Sample(uv);
    float alpha = center.a;

    // 原图只保留一点底子，让霓虹线更突出
    float3 rgb = center.rgb * 0.12f;

    // 霓虹色调随位置从青蓝渐变到洋红
    float hue = saturate(uv.x * 0.75f + uv.y * 0.25f);
    float3 neon = lerp(float3(0.05f, 0.90f, 1.00f),
                       float3(1.00f, 0.15f, 0.80f),
                       hue);

    float glow = smoothstep(0.03f, 0.35f, edge);
    float core = smoothstep(0.35f, 0.90f, edge);

    rgb += neon * glow * alpha;
    rgb += float3(1.0f, 1.0f, 1.0f) * core * alpha * 0.55f;

    // 轻微暗角
    float2 p = (uv - 0.5f) * aspect_scale(uv);
    float vignette = 1.0f - 0.35f * smoothstep(0.5f, 1.0f, length(p));
    rgb *= vignette;

    return float4(saturate(rgb), alpha);
}
