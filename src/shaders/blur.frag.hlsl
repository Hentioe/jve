cbuffer BlurUniforms : register(b0, space3)
{
  float2 g_TexelSize;     // 纹理单像素尺寸：传 [1.0 / Width, 1.0 / Height]
  float2 g_Direction;     // 模糊方向：横向传 [1.0, 0.0]，纵向传 [0.0, 1.0]
  float g_BlurIntensity;  // 模糊强度 (范围：1.0 - 10.0)
};

// Texture and Sampler in space2
Texture2D g_InputTexture     : register(t0, space2);
SamplerState g_LinearSampler : register(s0, space2);

struct PS_INPUT
{
  float4 pos : SV_POSITION;
  float2 uv  : TEXCOORD0;
};

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