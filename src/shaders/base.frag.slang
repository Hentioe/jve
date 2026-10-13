// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 3)]]
cbuffer BaseUniforms
{
    float u_invert;      // 0.0 为正常，1.0 为反色
    float u_grayscale;   // 0.0 为全彩，1.0 为完全灰阶
    float u_brightness;  // 0.0 为正常，正增亮，负变暗
    float u_contrast;    // 1.0 为正常，>1.0 增加对比度
    float u_gamma;       // 1.0 为正常
    int   u_channel;     // 0: 正常全彩, 1: R, 2: G, 3: B, 4: A
};

[[vk::binding(0, 2)]] Texture2D Texture;
[[vk::binding(0, 2)]] SamplerState Sampler;

// 人眼对 RGB 三原色的感知权重（ITU-R BT.709 标准）
static const float3 LUMINANCE_WEIGHTS = float3(0.2126, 0.7152, 0.0722);

[shader("fragment")]
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

    // 6. 单通道查看
    switch (u_channel) {
        case 1: color = float4(color.rrr, 1.0); break;  // 显示 R 通道灰阶（强制不透明）
        case 2: color = float4(color.ggg, 1.0); break;  // 显示 G 通道灰阶（强制不透明）
        case 3: color = float4(color.bbb, 1.0); break;  // 显示 B 通道灰阶（强制不透明）
        case 4: color = float4(color.aaa, 1.0); break;  // 显示 A 通道灰阶（强制不透明）
        default: break;                                 // 正常全彩（保留原 Alpha）
    }

    return color;
}
