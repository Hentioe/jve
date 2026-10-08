struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

// 16 字节对齐
cbuffer OverflowUniforms : register(b0, space3) {
    float u_Direction; // 位掩码：1=横向(左右)，2=纵向(上下)，3=全部
    float u_Thickness; // 边缘厚度（像素）
    float u_Alpha;     // 整体透明度（用于淡出）
    float padding;
};

float4 main(VSOutput input) : SV_Target {
    // 每个像素在 UV 空间中的步长，用于把距离换算成像素
    float2 step = float2(
        max(abs(ddx(input.uv.x)), 1e-6),
        max(abs(ddy(input.uv.y)), 1e-6)
    );

    // 到各边界的像素距离
    float left   = input.uv.x / step.x;
    float right  = (1.0 - input.uv.x) / step.x;
    float top    = input.uv.y / step.y;
    float bottom = (1.0 - input.uv.y) / step.y;

    int dir = (int)u_Direction;
    float distance = 1e9;
    if ((dir & 1) != 0) distance = min(distance, min(left, right)); // 横向：左右
    if ((dir & 2) != 0) distance = min(distance, min(top, bottom)); // 纵向：上下

    // 从边缘 (不透明) 向内 (透明) 渐变
    float thickness = max(u_Thickness, 1.0);
    float edge = 1.0 - smoothstep(0.0, thickness, distance);

    float alpha = saturate(edge * u_Alpha);
    float3 red = float3(0.90, 0.10, 0.10);

    // 直通 Alpha（混合状态使用 SRC_ALPHA）
    return float4(red, alpha);
}
