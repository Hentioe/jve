Texture2D u_MainTexture     : register(t0, space2);
SamplerState u_MainSampler : register(s0, space2);

Texture2D u_MaskTexture     : register(t1, space2);
SamplerState u_MaskSampler : register(s1, space2);

struct PSInput
{
  float4 Position : SV_POSITION;
  float2 TexCoord : TEXCOORD0;
};

float4 main(PSInput input) : SV_TARGET
{
  // 采样原图 RGB
  float3 color = u_MainTexture.Sample(u_MainSampler, input.TexCoord).rgb;
  
  // 采样 Mask 图 R 通道作为 Alpha
  float alpha = u_MaskTexture.Sample(u_MaskSampler, input.TexCoord).r;

  // 输出预乘 Alpha
  return float4(color * alpha, alpha);
}