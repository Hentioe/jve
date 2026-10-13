// 横幅背景：全屏 quad + uniform 决定可见的纵向区间。
// 不采样任何纹理，颜色完全由 uniform 提供，因此文字尺寸变化时无需重建 GPU 资源。
struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

[[vk::binding(0, 3)]]
cbuffer BannerUniforms
{
    float4 u_Color; // RGBA
    float2 u_Band;  // uv 空间可见区间：x=上边, y=下边（uv.y 向下增大）
    uint   u_Debug; // 非 0 时输出红色背景
};

[shader("fragment")]
float4 main(VSOutput input) : SV_Target
{
    float y = input.uv.y;
    if (y < u_Band.x || y > u_Band.y) {
        return float4(0.0, 0.0, 0.0, 0.0); // 区间外全透明
    }
    float4 color = u_Color;
    if (u_Debug != 0) {
        color = float4(1.0, 0.0, 0.0, color.a);
    }
    return color;
}
