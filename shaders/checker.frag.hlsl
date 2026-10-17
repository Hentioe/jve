struct VSOutput {
    float4 position : SV_Position;
};

float4 main(VSOutput input) : SV_Target {
    float tile_size = 12.0; // 棋盘格格子大小
    
    // input.position.xy 包含了当前像素在屏幕上的绝对坐标 (例如 0~1920, 0~1080)
    float2 coord = floor(input.position.xy / tile_size);
    
    // 计算奇偶性
    float pattern = fmod(coord.x + coord.y, 2.0);
    
    // 0 -> 暗灰 (100/255 ≈ 0.392), 1 -> 亮灰 (144/255 ≈ 0.565)
    float color_val = (pattern < 1.0) ? 0.392 : 0.565;
    
    return float4(color_val, color_val, color_val, 1.0);
}