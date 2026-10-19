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
  // 采样主纹理（内容链的纹理已是预乘 Alpha）
  float4 color = u_MainTexture.Sample(u_MainSampler, input.TexCoord);
  
  // 采样 Mask 图 R 通道作为遮罩
  float alpha = u_MaskTexture.Sample(u_MaskSampler, input.TexCoord).r;

  // 输出预乘 Alpha：RGB 与 Alpha 同时乘遮罩，混合状态不会再乘一次
  return float4(color.rgb * alpha, color.a * alpha);
}