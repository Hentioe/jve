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

float gradient_noise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);

    return lerp(
        lerp(dot(hash22(i + float2(0.0, 0.0)), f - float2(0.0, 0.0)),
             dot(hash22(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
        lerp(dot(hash22(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
             dot(hash22(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
}

float4 main(VSOutput input) : SV_Target {
    // 1. 进一步放大团块尺寸 (1.5)，更好地铺满整个屏幕
    float2 uv = input.uv * 1.5; 
    float t = time;

    float2 dir1 = float2(cos(t * 0.6), sin(t * 0.4));
    float2 dir2 = float2(sin(t * 0.5), cos(t * 0.7));

    // 域扭曲 (Domain Warping)
    float2 q;
    q.x = gradient_noise(uv + dir1);
    q.y = gradient_noise(uv + dir2);

    float2 r;
    r.x = gradient_noise(uv + 1.5 * q + float2(1.7, 9.2) + t * 0.15);
    r.y = gradient_noise(uv + 1.5 * q + float2(8.3, 2.8) - t * 0.12);

    // 2. 算基础噪声图样
    float raw_density = gradient_noise(uv + 2.0 * r) * 0.5 + 0.5;
    float d = smoothstep(0.1, 0.8, raw_density);

    // 3. 解决“差异过大、过透”的关键：
    // min_alpha = 0.45: 垫高底线，最薄的地方也有 45% 的蓝色遮罩，彻底杜绝接近 0 的绝透区域
    // max_alpha = 0.80: 提升顶线，最浓的地方达到 80% 的不透明度，增加厚重感
    float min_alpha = 0.45; 
    float max_alpha = 0.80; 
    float alpha = lerp(min_alpha, max_alpha, d);

    return float4(float3(0.12, 0.42, 0.88) * alpha, alpha);
}