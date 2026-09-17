Texture2D g_MainTex : register(t0, space2);
SamplerState g_Sampler : register(s0, space2);

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

float SpatialDitherNoise(float2 uv)
{
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

float4 main(PS_INPUT input) : SV_TARGET
{
    // 1. 采样中心点完整的 RGBA
    float4 mainTex = g_MainTex.Sample(g_Sampler, input.uv);
    float3 c = mainTex.rgb;
    float alpha = mainTex.a;

    // 如果 Alpha 为 0（完全透明），直接返回原始采样，避免黑边和无用计算
    if (alpha <= 0.001)
    {
        return mainTex;
    }

    // 获取纹理尺寸
    float width, height;
    g_MainTex.GetDimensions(width, height);
    float2 texelSize = 1.0 / float2(width, height);
    float2 uv = input.uv;

    // 2. 采样四邻域 RGB
    float3 l = g_MainTex.Sample(g_Sampler, uv + float2(-texelSize.x, 0)).rgb;
    float3 r = g_MainTex.Sample(g_Sampler, uv + float2( texelSize.x, 0)).rgb;
    float3 t = g_MainTex.Sample(g_Sampler, uv + float2(0, -texelSize.y)).rgb;
    float3 b = g_MainTex.Sample(g_Sampler, uv + float2(0,  texelSize.y)).rgb;

    // 3. 自适应轻微锐化
    float3 minColor = min(c, min(min(l, r), min(t, b)));
    float3 maxColor = max(c, max(max(l, r), max(t, b)));
    
    float3 amp = saturate(min(minColor, 1.0 - maxColor) / (maxColor + 0.0001));
    float3 sharpMask = (4.0 * c - l - r - t - b);
    float3 color = c + sharpMask * 0.20 * sqrt(amp);

    // 4. 防色带抖动
    float noise = (SpatialDitherNoise(uv * float2(width, height)) - 0.5) * (1.0 / 255.0);
    color += noise;

    // 保留原始 Alpha 通道输出
    return float4(saturate(color), alpha);
}