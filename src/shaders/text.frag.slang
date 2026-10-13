// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 2)]] Texture2D Texture;
[[vk::binding(0, 2)]] SamplerState Sampler;

// 文字颜色与调试开关由外部参数传入，纹理只承载覆盖率（灰度）
[[vk::binding(0, 3)]]
cbuffer TextUniforms
{
    float4 u_Color;
    uint   u_Debug; // 非 0 时输出红色背景，便于观察 quad 的位置与大小
};

[shader("fragment")]
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
