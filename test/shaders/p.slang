[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
    const float u_segments   = 60.0f;   
    const float u_refraction = 0.04f;   
    const float u_blur       = 0.015f;  

    // 修改1：基于 Y 坐标生成波形，使条纹横向排列
    float wave = sin(input.UV.y * u_segments * 6.283185f);
    float distortY = wave * u_refraction;
    
    float4 color = float4(0.0f, 0.0f, 0.0f, 0.0f);
    
    // 修改2：将折射与模糊采样偏移应用到 Y 轴上
    color += g_BackgroundTex.Sample(float2(input.UV.x, input.UV.y + distortY));
    color += g_BackgroundTex.Sample(float2(input.UV.x, input.UV.y + distortY + u_blur));
    color += g_BackgroundTex.Sample(float2(input.UV.x, input.UV.y + distortY - u_blur));
    color /= 3.0f;
    
    float shadow = 0.95f + 0.05f * wave;
    
    return float4(color.rgb * shadow, color.a);
}
