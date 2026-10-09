float4 main(float2 uv : TEXCOORD0) : SV_Target
{
    // 利用屏幕空间偏导数自动推导长宽比，防止拉伸
    float2 dTex = float2(length(ddx(uv)), length(ddy(uv)));
    float aspect = dTex.y / dTex.x;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float dist = length(p);
    float radius = 0.25; // 日食中心遮挡圆的半径

    // 计算到遮挡圆边缘的绝对距离 (0 代表刚好在边缘上)
    float d = dist - radius;

    // 内圈边缘抗锯齿（圆内为 0，圆外为 1）
    float aa = fwidth(dist);
    float mask = smoothstep(-aa, aa, d);

    // 双重指数衰减模型（模拟日食日冕）：
    // 1. 紧贴边缘的高亮细圈 (衰减系数 70.0，使亮度快速下跌)
    // 2. 向外扩散的柔和日冕 (衰减系数 12.0，提供极度平滑的余辉)
    float coreRim   = exp(-d * 70.0); 
    float outerHalo = exp(-d * 12.0);

    // 混合两层光晕并做边缘掩码
    float intensity = (coreRim * 0.55 + outerHalo * 0.45) * mask;

    // 太阳暖色调：
    // 紧贴边缘最亮处为高亮暖金白 (1.0, 0.95, 0.82)，向外过渡为温润的琥珀金光芒 (1.0, 0.62, 0.22)
    float3 warmAmber = float3(1.0, 0.62, 0.22);
    float3 brightWhiteGold = float3(1.0, 0.95, 0.82);
    float3 sunColor = lerp(warmAmber, brightWhiteGold, saturate(coreRim));

    return float4(sunColor, saturate(intensity));
}