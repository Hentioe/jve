struct VSOutput {
    float4 position : SV_Position;
};

// 配置参数
static const float SCALE = 1.0;
static const float2 TILE_SIZE = float2(90.0, 45.0); // 瓷砖的长和宽（像素）

// 8 色马卡龙彩虹色谱
float3 rainbowPalette(uint i) {
    if (i == 0u) return float3(1.00, 0.82, 0.82); // 柔红 / 樱花粉
    if (i == 1u) return float3(1.00, 0.88, 0.72); // 暖橙 / 杏黄
    if (i == 2u) return float3(0.98, 0.96, 0.73); // 鹅黄 / 明黄
    if (i == 3u) return float3(0.82, 0.94, 0.80); // 薄荷绿
    if (i == 4u) return float3(0.76, 0.92, 0.96); // 冰蓝 / 天蓝
    if (i == 5u) return float3(0.78, 0.84, 0.98); // 罗兰紫 / 靛蓝
    if (i == 6u) return float3(0.88, 0.80, 0.96); // 香草紫
    return float3(0.96, 0.80, 0.90);              // 蔷薇粉
}

[shader("fragment")]
float4 main(VSOutput input) : SV_Target {
    // 加上大偏移量，完美规避负数取模和位移坑
    float2 px = input.position.xy / SCALE + 1048576.0;

    // 1. 计算行号与错位逻辑（奇数行水平错开半块砖）
    float row = floor(px.y / TILE_SIZE.y);
    float xOffset = (fmod(row, 2.0) == 0.0) ? 0.0 : TILE_SIZE.x * 0.5;
    float adjustedX = px.x + xOffset;

    // 计算当前像素所在的瓷砖 ID
    int2 tileID = int2(int(floor(adjustedX / TILE_SIZE.x)), int(row));

    // 计算像素在当前瓷砖内部的相对局部坐标 (0.0 到 1.0)
    float2 localUV = float2(
        frac(adjustedX / TILE_SIZE.x),
        frac(px.y / TILE_SIZE.y)
    );

    // 2. 精细化砖缝计算（大幅收窄缝隙，并加入平滑抗锯齿）
    float edgeX = min(localUV.x, 1.0 - localUV.x);
    float edgeY = min(localUV.y, 1.0 - localUV.y);
    
    float gapThick = 0.015; // 极为纤细的现代美缝厚度
    float smoothPx = 0.003; // 抗锯齿过渡区
    
    float borderMask = max(
        1.0 - smoothstep(0.0, smoothPx, edgeX - gapThick),
        1.0 - smoothstep(0.0, smoothPx, edgeY - gapThick)
    );

    // 3. 利用哈希为每块独立的瓷砖随机分配马卡龙色谱
    uint hash = uint(abs(tileID.x * 73856093 ^ tileID.y * 19349663));
    uint colorIdx = hash % 8u;
    float3 baseCol = rainbowPalette(colorIdx);

    // 4. 边缘微弱凹陷阴影（让砖块边缘向缝隙自然过渡，增强立体层次）
    float bevel = smoothstep(0.0, 0.08, edgeX) * smoothstep(0.0, 0.08, edgeY);
    float3 tileCol = baseCol * (0.90 + 0.10 * bevel);

    // 5. 砖缝颜色（采用高级的深灰微暖色，而不是生硬的纯黑或厚重灰）
    float3 mortarCol = float3(0.32, 0.32, 0.35);
    
    // 6. 最终合成
    float3 finalCol = lerp(tileCol, mortarCol, borderMask);

    return float4(finalCol, 1.0);
}
