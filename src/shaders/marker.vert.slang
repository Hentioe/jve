[[vk::binding(0, 1)]]
cbuffer MarkerUniforms
{
    float2 u_Pos;
};

struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

[shader("vertex")]
VSOutput main(uint vertexID : SV_VertexID) {
    float2 quad[6] = {
        float2(-0.1, -0.1), float2( 0.1, -0.1), float2(-0.1,  0.1),
        float2(-0.1,  0.1), float2( 0.1, -0.1), float2( 0.1,  0.1)
    };

    float2 localPos = quad[vertexID];

    VSOutput output;
    output.pos = float4(u_Pos + localPos, 0.0, 1.0);
    output.uv  = localPos * 10.0; // 范围 [-1.0, 1.0]
    return output;
}
