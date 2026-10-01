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

    // 利用屏幕空间偏导数自动计算宽高比 (Width / Height)
    // ddx(p) 和 ddy(p) 分别代表 UV 在屏幕物理像素 X、Y 方向的变化率
    float aspect = length(ddy(p)) / max(length(ddx(p)), 0.00001);
    
    // 对 X 轴做宽高比校正，使 X 和 Y 在物理像素尺度上等比
    float2 pCorrected = float2(p.x * aspect, p.y);

    // 计算校正后的距离
    float d = length(pCorrected);

    // 1. 尺寸与外边框参数
    float outerRadius = 0.55;                       // 整体圆外径（包含白色边框）
    float borderWidth = 0.07;                       // 薄白色外圈厚度
    float innerRadius = outerRadius - borderWidth;  // 内部绿色实心的半径

    // 2. 抗锯齿宽度计算
    float delta = fwidth(d);

    // 3. 计算整体 Alpha 和 内部绿色部分的遮罩
    float outerAlpha = 1.0 - smoothstep(outerRadius - delta, outerRadius + delta, d);
    float innerMask  = 1.0 - smoothstep(innerRadius - delta, innerRadius + delta, d);

    // 4. 颜色定义
    float3 greenColor = float3(0.52, 0.73, 0.43);   // 柔和亮绿色
    float3 whiteColor = float3(1.0, 1.0, 1.0);      // 薄白色外圈

    // 5. 颜色插值：中心为绿色，往外过渡到白色
    float3 finalColor = lerp(whiteColor, greenColor, innerMask);

    // 6. 输出预乘 Alpha
    return float4(finalColor * outerAlpha, outerAlpha);
}