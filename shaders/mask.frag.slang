// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 2)]] Texture2D u_MainTexture;
[[vk::binding(0, 2)]] SamplerState u_MainSampler;

[[vk::binding(1, 2)]] Texture2D u_MaskTexture;
[[vk::binding(1, 2)]] SamplerState u_MaskSampler;

struct PSInput
{
  float4 Position : SV_POSITION;
  float2 TexCoord : TEXCOORD0;
};

[shader("fragment")]
float4 main(PSInput input) : SV_TARGET
{
  // 采样原图 RGB
  float3 color = u_MainTexture.Sample(u_MainSampler, input.TexCoord).rgb;
  
  // 采样 Mask 图 R 通道作为 Alpha
  float alpha = u_MaskTexture.Sample(u_MaskSampler, input.TexCoord).r;

  // 输出预乘 Alpha
  return float4(color * alpha, alpha);
}
