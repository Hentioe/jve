struct VSOutput {
    float4 position : SV_Position;
};

// 配置参数
static const float STRIPE_W = 30.0; // 每道条纹的宽度（像素）
static const float SCALE    = 1.0;  // 缩放比例

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
    float2 px = input.position.xy / SCALE;

    // 1. 计算 45 度斜向投影距离（加上大偏移量，完美规避负数取模的平台兼容性坑）
    float diag = px.x + px.y + 1048576.0;
    
    int   stripeIndex = int(floor(diag / STRIPE_W));
    float posInStripe = fmod(diag, STRIPE_W);

    // 2. 奇偶交替模式：
    //    偶数索引 (stripeIndex % 2 == 0) -> 彩虹纯色
    //    奇数索引 (stripeIndex % 2 != 0) -> 纯白间隔
    float3 baseCol;
    if (stripeIndex % 2 == 0) {
        uint colorIdx = uint((stripeIndex / 2) % 8);
        baseCol = rainbowPalette(colorIdx);
    } else {
        baseCol = float3(1.0, 1.0, 1.0); // 纯白间隔条纹
    }

    // 3. 计算条纹交界处的精致微线，增强立体裁切感
    float distToEdge = min(posInStripe, STRIPE_W - posInStripe);
    float edgeMask   = 1.0 - smoothstep(0.0, 1.2, distToEdge);

    // 4. 边缘压暗合成（白色和彩色交界处都有清晰的边界阴影）
    float3 edgeColor = baseCol * 0.86;
    float3 finalCol  = lerp(baseCol, edgeColor, edgeMask * 0.35);

    return float4(finalCol, 1.0);
}
