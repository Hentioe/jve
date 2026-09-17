// 对应 slot 0 的 Fragment Uniform 数据
cbuffer FragUniforms : register(b0, space3)
{
    int u_invert;        // 0 代表正常，1 代表反转颜色
    float3 padding;      // 补齐 16 字节内存对齐
};

Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
    float4 color = Texture.Sample(Sampler, uv);
    if (u_invert == 1) {
        color.rgb = 1.0 - color.rgb;
    }
    return color;
}