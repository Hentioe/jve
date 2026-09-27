cbuffer BaseUniforms : register(b0, space3)
{
    float u_invert;      // 0.0 为正常，1.0 为反色
    float u_grayscale;   // 0.0 为全彩，1.0 为完全灰阶（0.5 为半去色）
    float u_brightness;  // 0.0 为正常，正增亮，负变暗
    float u_contrast;    // 1.0 为正常，>1.0 增加对比度
    float u_gamma;       // 1.0 为正常
    float3 padding;      // 补齐 16 字节对齐 (5 * 4 = 20 字节，加 12 字节凑齐 32 字节)
};

Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

// 人眼对 RGB 三原色的感知权重（ITU-R BT.709 标准）
static const float3 LUMINANCE_WEIGHTS = float3(0.2126, 0.7152, 0.0722);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
    float4 color = Texture.Sample(Sampler, uv);

    // 1. 反色控制 (Invert)
    color.rgb = lerp(color.rgb, 1.0 - color.rgb, u_invert);

    // 2. 灰阶化 / 去色 (Grayscale / Desaturate)
    // 利用点积算出符合人眼视觉感知的亮度值（加权平均）
    float gray = dot(color.rgb, LUMINANCE_WEIGHTS);
    color.rgb = lerp(color.rgb, float3(gray, gray, gray), u_grayscale);

    // 3. 亮度调整 (Brightness)
    color.rgb += u_brightness;

    // 4. 对比度调整 (Contrast)
    color.rgb = (color.rgb - 0.5) * u_contrast + 0.5;

    // 5. Gamma 校正
    color.rgb = pow(max(color.rgb, 0.0), u_gamma);

    return color;
}