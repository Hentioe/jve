// 简单的伪随机哈希函数，用于生成微噪点以消除暗部色阶断层
float hash(float2 p)
{
    return frac(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

[shader("fragment")]
float4 main(float2 uv : TEXCOORD0) : SV_Target
{
    // 将 UV 坐标从 [0, 1] 映射到 [-1, 1]
    float2 p = uv * 2.0 - 1.0;
    
    // 将暗角中心稍微向左上方偏移（营造自然的光照汇聚感，而不是死板的正中）
    float2 centerOffset = float2(-0.2, -0.2);
    float dist = length(p - centerOffset);
    
    // 丰富色彩层次：中心是带有高级感的冷灰蓝，边缘压入更深的暗色
    float3 centerColor = float3(0.14, 0.17, 0.24); // 微微提高亮度，带点冷调青蓝
    float3 edgeColor   = float3(0.03, 0.03, 0.05); // 边缘保留极深的压边
    
    // 使用 smoothstep 做基础放射状渐变
    float t = smoothstep(0.0, 1.5, dist);
    float3 finalColor = lerp(centerColor, edgeColor, t);
    
    // 叠加极微弱的高频噪点（约占 1-2 个灰度级），彻底消除深色渐变的条纹断层
    float noise = (hash(uv * 200.0) - 0.5) * (2.0 / 255.0);
    finalColor += noise;
    
    return float4(finalColor, 1.0);
}
