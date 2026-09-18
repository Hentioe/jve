Texture2D Texture : register(t0, space2);
SamplerState Sampler : register(s0, space2);

struct PSInput {
  float4 pos : SV_POSITION;
  float2 uv  : TEXCOORD0;
};

float4 main(PSInput input) : SV_Target {
  return Texture.Sample(Sampler, input.uv); // 直接采样纹理并原样输出
}