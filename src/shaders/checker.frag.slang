struct VSOutput {
    float4 position : SV_Position;
};

[shader("fragment")]
float4 main(VSOutput input) : SV_Target {
    float tile_size = 22.0;   // 棋盘格格子大小（像素）

    float2 coord = floor(input.position.xy / tile_size);
    float pattern = fmod(coord.x + coord.y, 2.0);

    // 0 -> 暗 0.855, 1 -> 亮 0.925
    float v = (pattern < 1.0) ? 0.855 : 0.925;

    return float4(v, v, v, 1.0);
}
