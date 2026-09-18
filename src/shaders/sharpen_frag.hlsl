// 纯片段着色器：SharpenPS.hlsl
cbuffer SharpenUniforms : register(b0, space3)
{
    float strength;     // 范围：1.0 ~ 10.0
    float2 textureSize; // 纹理分辨率，如 [512.0, 512.0]
    float padding;      
};

Texture2D inputTexture : register(t0, space2);
SamplerState inputSampler : register(s0, space2);

struct PSInput
{
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0; // 必须与 Vertex Shader 输出结构体严格对齐
};

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