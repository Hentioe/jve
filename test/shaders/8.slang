// 编号 8：长曝光变焦（Zoom Burst）
// 模拟拍照时快速推近镜头：沿着从当前像素指向画面中心的方向多次采样，
// 让亮部拖出放射状光轨。RGB 三通道使用略有差异的缩放量，形成边缘色散。

[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
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
    float2 p = (uv - 0.5f) * scale;
    float radius = length(p);

    float4 acc_r = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float4 acc_g = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float4 acc_b = float4(0.0f, 0.0f, 0.0f, 0.0f);
    float wsum = 0.0f;

    const int N = 16;
    [unroll]
    for (int i = 0; i < N; i++)
    {
        float t = float(i) / float(N - 1);
        float w = 1.0f - 0.55f * t;

        // 越靠外，采样点向中心移动得越多，形成放射状拖影
        float zoom = 1.0f - 0.26f * t;
        float zoom_r = zoom - 0.025f * t;
        float zoom_b = zoom + 0.025f * t;

        float2 uv_r = saturate(p * zoom_r / scale + 0.5f);
        float2 uv_g = saturate(p * zoom / scale + 0.5f);
        float2 uv_b = saturate(p * zoom_b / scale + 0.5f);

        acc_r += g_BackgroundTex.Sample(uv_r) * w;
        acc_g += g_BackgroundTex.Sample(uv_g) * w;
        acc_b += g_BackgroundTex.Sample(uv_b) * w;
        wsum += w;
    }

    // 分别解预乘后组合通道，再重新预乘
    float alpha = acc_g.a / wsum;
    float3 rgb = float3(
        acc_r.r / max(acc_r.a, 1e-4f),
        acc_g.g / max(acc_g.a, 1e-4f),
        acc_b.b / max(acc_b.a, 1e-4f)) * alpha;

    // 中心稍微提亮，模拟变焦时中心曝光更集中
    rgb += float3(0.04f, 0.05f, 0.08f) * exp(-radius * radius * 7.0f) * alpha;

    // 边缘压暗
    float vignette = 1.0f - 0.35f * smoothstep(0.35f, 1.0f, radius);
    rgb *= vignette;

    return float4(saturate(rgb), saturate(alpha));
}
