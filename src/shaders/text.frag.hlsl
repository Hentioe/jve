Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

// 文字颜色与调试开关由外部参数传入，纹理只承载覆盖率（灰度）
cbuffer TextUniforms : register(b0, space3)
{
    float4 u_Color;
    uint   u_Debug; // 非 0 时输出红色背景，便于观察 quad 的位置与大小
};

float4 main(float2 uv : TEXCOORD0) : SV_Target
{
    float coverage = Texture.Sample(Sampler, uv).r;
    if (u_Debug != 0) {
        // debug：红色作为不透明底色，文字按其真实 alpha 叠在红底上，
        // 这样半透明色也能透出红色（而非被强制成不透明）。
        return float4(lerp(float3(1.0, 0.0, 0.0), u_Color.rgb, coverage * u_Color.a), 1.0);
    }
    return float4(u_Color.rgb, coverage * u_Color.a);
}
