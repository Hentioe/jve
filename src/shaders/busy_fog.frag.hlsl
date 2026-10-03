struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

// 16 字节对齐
cbuffer FragUniforms : register(b0, space3) {
    float time;
    float3 padding;
};

float2 hash22(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * frac(sin(p) * 43758.5453123);
}

float grad_noise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    return lerp(
        lerp(dot(hash22(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
             dot(hash22(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
        lerp(dot(hash22(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
             dot(hash22(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
}

// 低频定大团块，高频加内部细节
float fbm(float2 p) {
    return grad_noise(p) * 0.65 + grad_noise(p * 2.7 + 13.7) * 0.35;
}

float4 main(VSOutput input) : SV_Target {
    float2 uv = input.uv * 1.4;
    float t = time;

    // 两层独立漂移（李萨如轨迹），让不同团块交错游走
    float2 w1 = float2(cos(t * 0.13), sin(t * 0.17)) * 1.3;
    float2 w2 = float2(sin(t * 0.11), cos(t * 0.19)) * 1.6;

    // 域扭曲 (Domain Warping)
    float2 q;
    q.x = fbm(uv + w1);
    q.y = fbm(uv + w2);

    float2 r;
    r.x = fbm(uv + 1.4 * q + float2(1.7, 9.2) + t * 0.10);
    r.y = fbm(uv + 1.4 * q + float2(8.3, 2.8) - t * 0.09);

    // 基础噪声图样，收窄区间让团块更分明
    float density = fbm(uv + 1.8 * r) * 0.5 + 0.5;
    float d = smoothstep(0.28, 0.72, density);

    // 薄处 = 压暗图片的深色蒙版；浓处 = 明亮的雾
    float alpha = lerp(0.45, 0.95, d);
    float3 color = lerp(float3(0.02, 0.05, 0.12), float3(0.35, 0.60, 1.0), d);

    // 缓慢呼吸，暗示任务仍在进行
    alpha *= 0.92 + 0.08 * sin(t * 1.3);

    return float4(color, alpha);
}
