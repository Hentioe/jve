
// 把这个着色器的参数移除，改成纯粹的颜色反转着色器
Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
    float4 color = Texture.Sample(Sampler, uv);
    color.rgb = 1.0 - color.rgb;
    return color;
}