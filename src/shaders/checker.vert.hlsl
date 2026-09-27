struct VSOutput {
    float4 position : SV_Position;
};

VSOutput main(uint vertex_id : SV_VertexID) {
    VSOutput output;
    // 利用 3 个顶点生成覆盖全屏的大三角形：
    // id=0 -> (-1, -1)
    // id=1 -> ( 3, -1)
    // id=2 -> (-1,  3)
    float2 pos = float2(
        (vertex_id == 1) ? 3.0 : -1.0,
        (vertex_id == 2) ? 3.0 : -1.0
    );
    output.position = float4(pos, 0.0, 1.0);
    return output;
}