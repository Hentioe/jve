Texture2D    uTex    : register(t0, space2);
SamplerState uSampler : register(s0, space2);

float4 main(float4  svPos  : SV_Position,
            float2  vUV    : TEXCOORD0,
            float4  vColor : TEXCOORD1) : SV_Target
{
    float4 texel = uTex.Sample(uSampler, vUV);
    return texel * vColor;
}