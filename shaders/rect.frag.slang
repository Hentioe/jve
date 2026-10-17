// 纯色矩形背景：全屏 quad + uniform 决定的 uv 矩形区间，不采样纹理。
// 与 banner.frag 同源，只是把一维纵向带升级为二维矩形，因此改色/改位置只更新 uniform。
struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

[[vk::binding(0, 3)]]
cbuffer RectUniforms
{
    float4 u_Color; // RGBA
    float4 u_Rect;  // uv 空间矩形：x=左, y=上, z=右, w=下（uv.y 向下增大）
    uint   u_Debug; // 非 0 时输出红色背景
};

[shader("fragment")]
float4 main(VSOutput input) : SV_Target
{
    float2 uv = input.uv;
    if (uv.x < u_Rect.x || uv.x > u_Rect.z || uv.y < u_Rect.y || uv.y > u_Rect.w) {
        return float4(0.0, 0.0, 0.0, 0.0); // 区间外全透明
    }
    float4 color = u_Color;
    if (u_Debug != 0) {
        color = float4(1.0, 0.0, 0.0, color.a);
    }
    return color;
}
