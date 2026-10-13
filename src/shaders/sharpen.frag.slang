// 纯片段着色器：SharpenPS
// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 3)]]
cbuffer SharpenUniforms
{
    float strength;     // 范围：1.0 ~ 10.0
    float2 textureSize; // 纹理分辨率，如 [512.0, 512.0]
};

[[vk::binding(0, 2)]] Texture2D inputTexture;
[[vk::binding(0, 2)]] SamplerState inputSampler;

struct PSInput
{
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0; // 必须与 Vertex Shader 输出结构体严格对齐
};

[shader("fragment")]
float4 main(PSInput input) : SV_Target
{
    float2 uv = input.texcoord;
    float2 texelSize = 1.0 / textureSize;

    float4 center = inputTexture.Sample(inputSampler, uv);
    float4 top    = inputTexture.Sample(inputSampler, uv + float2(0.0, -texelSize.y));
    float4 bottom = inputTexture.Sample(inputSampler, uv + float2(0.0,  texelSize.y));
    float4 left   = inputTexture.Sample(inputSampler, uv + float2(-texelSize.x, 0.0));
    float4 right  = inputTexture.Sample(inputSampler, uv + float2( texelSize.x, 0.0));

    float3 blur = (top.rgb + bottom.rgb + left.rgb + right.rgb) * 0.25;
    float factor = strength * 0.15;
    float3 sharpened = center.rgb + (center.rgb - blur) * factor;

    return float4(saturate(sharpened), center.a);
}
