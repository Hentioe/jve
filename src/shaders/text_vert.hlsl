struct VSInput
{
    float2 aPos   : TEXCOORD0;   // NDC 位置
    float2 aUV    : TEXCOORD1;   // UV
    float4 aColor : TEXCOORD2;   // 顶点色（整体透明度可以塞这里）
};

struct VSOutput
{
    float4 Position : SV_Position;
    float2 vUV      : TEXCOORD0;
    float4 vColor   : TEXCOORD1;
};

VSOutput main(VSInput input)
{
    VSOutput output;
    output.Position = float4(input.aPos, 0.0f, 1.0f);
    output.vUV      = input.aUV;
    output.vColor   = input.aColor;
    return output;
}