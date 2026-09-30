Texture2D u_MainTexture     : register(t0, space2);
SamplerState u_MainSampler : register(s0, space2);

Texture2D u_MaskTexture     : register(t1, space2);
SamplerState u_MaskSampler : register(s1, space2);

struct PSInput
{
    float4 Position : SV_POSITION;
    float2 TexCoord : TEXCOORD0; // [-1.0, 1.0]
};

float4 main(PSInput input) : SV_TARGET
{
    float2 p = input.TexCoord;
    float d = length(p);

    // 1. 尺寸与外边框参数
    float outerRadius = 0.55;                       // 增大后的整体圆外径（包含白色边框）
    float borderWidth = 0.07;                       // 薄白色外圈厚度
    float innerRadius = outerRadius - borderWidth;  // 内部绿色实心的半径

    // 2. 抗锯齿宽度计算
    float delta = fwidth(d);

    // 3. 计算整体 Alpha 和 内部绿色部分的遮罩
    float outerAlpha = 1.0 - smoothstep(outerRadius - delta, outerRadius + delta, d);
    float innerMask  = 1.0 - smoothstep(innerRadius - delta, innerRadius + delta, d);

    // 4. 颜色定义
    float3 greenColor = float3(0.52, 0.73, 0.43);   // 右图柔和亮绿色
    float3 whiteColor = float3(1.0, 1.0, 1.0);      // 薄白色外圈

    // 5. 颜色插值：中心为绿色，往外过渡到白色
    float3 finalColor = lerp(whiteColor, greenColor, innerMask);

    // 6. 输出预乘 Alpha
    return float4(finalColor * outerAlpha, outerAlpha);
}