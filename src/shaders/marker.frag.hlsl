// 外部传递的常量缓冲区
cbuffer MarkerUniforms : register(b0, space3)
{
    float u_OuterRadiusPx; // 整体圆外径 (像素)
    float u_BorderWidthPx; // 白色外边框厚度 (像素)
    float2 u_Padding;      // 补齐 16 字节 (Vector4) 边界对齐
};

struct PSInput
{
    float4 Position : SV_POSITION;
    float2 TexCoord : TEXCOORD0; // [-1.0, 1.0]
};

float4 main(PSInput input) : SV_TARGET
{
    float2 p = input.TexCoord;

    // 1. 获取屏幕像素步长并防止除以 0
    float2 pixelStep = float2(
        max(length(ddx(p)), 0.00001),
        max(length(ddy(p)), 0.00001)
    );

    // 2. 转换到物理像素距离空间
    float2 pInPixels = p / pixelStep;
    float dInPixels  = length(pInPixels);

    // 3. 从 cbuffer 获取尺寸参数
    float outerRadiusPx = u_OuterRadiusPx;
    float borderWidthPx = u_BorderWidthPx;
    float innerRadiusPx = outerRadiusPx - borderWidthPx;

    // 4. 1-Pixel 物理像素级抗锯齿
    float outerAlpha = 1.0 - smoothstep(outerRadiusPx - 1.0, outerRadiusPx + 1.0, dInPixels);
    float innerMask  = 1.0 - smoothstep(innerRadiusPx - 1.0, innerRadiusPx + 1.0, dInPixels);

    // 5. 颜色定义与插值
    float3 greenColor = float3(0.52, 0.73, 0.43);   // 柔和亮绿色
    float3 whiteColor = float3(1.0, 1.0, 1.0);     // 纯白外圈

    float3 finalColor = lerp(whiteColor, greenColor, innerMask);

    // 6. 输出预乘 Alpha
    return float4(finalColor * outerAlpha, outerAlpha);
}
