Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

float4 main(float2 uv : TEXCOORD0) : SV_Target {
    return Texture.Sample(Sampler, uv);
}