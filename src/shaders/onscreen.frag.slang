// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 2)]] Texture2D Texture;
[[vk::binding(0, 2)]] SamplerState Sampler;

struct PSInput {
  float4 pos : SV_POSITION;
  float2 uv  : TEXCOORD0;
};

[shader("fragment")]
float4 main(PSInput input) : SV_Target {
  return Texture.Sample(Sampler, input.uv); // 直接采样纹理并原样输出
}
