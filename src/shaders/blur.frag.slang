// 注意：SDL_GPU 把纹理与采样器当作同一绑定的两个独立资源，在运行时配对为组合采样器，
// 因此二者会共享相同的 (set, binding)。Slang 会对此报 E39001「显式绑定重叠」警告，
// 这是预期行为，故在此局部屏蔽该警告。
#pragma warning(disable: 39001)

[[vk::binding(0, 3)]]
cbuffer BlurUniforms
{
  float2 g_TexelSize;     // 纹理单像素尺寸：传 [1.0 / Width, 1.0 / Height]
  float2 g_Direction;     // 模糊方向：横向传 [1.0, 0.0]，纵向传 [0.0, 1.0]
  float g_BlurIntensity;  // 模糊强度 (范围：1.0 - 10.0)
};

// Texture and Sampler in space2
[[vk::binding(0, 2)]] Texture2D g_InputTexture;
[[vk::binding(0, 2)]] SamplerState g_LinearSampler;

struct PS_INPUT
{
  float4 pos : SV_POSITION;
  float2 uv  : TEXCOORD0;
};

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
  // 将强度限制在 1.0 到 10.0
  float intensity = clamp(g_BlurIntensity, 1.0f, 10.0f);
  
  // 根据强度动态计算高斯标准差 (Sigma) 与采样半径 (Radius)
  float sigma = intensity;
  float twoSigmaSq = 2.0f * sigma * sigma;
  int radius = (int)ceil(intensity * 1.5f);

  float4 colorAcc = float4(0.0f, 0.0f, 0.0f, 0.0f);
  float weightSum = 0.0f;

  // 1D 可分离高斯采样
  for (int i = -radius; i <= radius; ++i)
  {
    // 高斯公式: G(x) = exp(-x^2 / (2 * sigma^2))
    float weight = exp(-(float)(i * i) / twoSigmaSq);
    
    float2 offset = g_Direction * ((float)i * g_TexelSize);
    colorAcc += g_InputTexture.Sample(g_LinearSampler, input.uv + offset) * weight;
    weightSum += weight;
  }

  // 归一化防止图像变暗
  return colorAcc / weightSum;
}
