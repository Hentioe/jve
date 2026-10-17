struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

// 16 字节对齐
cbuffer FogUniforms : register(b0, space3) {
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

// ---------------------------------------------------------------
// 色块：每种颜色一个独立的噪声场，谁强谁占据该处
// 红、黄各两个场（面积更大），蓝、黑、洋红各一个，绿只作点缀
// ---------------------------------------------------------------
#define COLOR_N 8

static const float3 COLORS[COLOR_N] = {
    float3(0.88, 0.07, 0.10), // 红 A
    float3(0.93, 0.14, 0.07), // 红 B（略偏橙红）
    float3(0.98, 0.83, 0.04), // 黄 A
    float3(0.93, 0.88, 0.10), // 黄 B（略偏柠檬黄）
    float3(0.10, 0.20, 0.85), // 蓝
    float3(0.09, 0.09, 0.11), // 深灰黑
    float3(0.88, 0.10, 0.58), // 洋红
    float3(0.02, 0.52, 0.26)  // 绿（点缀）
};

// 偏置：越大，该颜色占的面积越多
static const float BIAS[COLOR_N] = {
    0.10, 0.06, 0.10, 0.05, 0.08, 0.08, -0.08, -0.20
};

static const float COLOR_SCALE = 1.7;  // 色块密度：越小块越大
static const float SHARP       = 9.0;  // 色块边界锐度：越小越柔、越糊；越大越硬

// 根据屏幕上实际的宽高比，放大长边的采样坐标，
// 这样图片变宽时横向的雾变多，而不是被拉伸。
// 原理：ddx(uv.x)=1/宽像素，ddy(uv.y)=1/高像素，两者之比就是宽高比。
float2 aspect_scale(float2 uv) {
    float dx = max(abs(ddx(uv.x)), 1e-6);
    float dy = max(abs(ddy(uv.y)), 1e-6);
    float aspect = clamp(dy / dx, 0.1, 10.0);   // 宽 / 高
    return (aspect >= 1.0) ? float2(aspect, 1.0)
                           : float2(1.0, 1.0 / aspect);
}

float4 main(VSOutput input) : SV_Target {
    // 短边保持原有的密度，长边按比例增加
    float2 uv = input.uv * aspect_scale(input.uv) * 1.4;
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

    // 扭曲后的坐标：既用来算浓度，也用来给色块定位，
    // 这样色块边界会跟着雾的形状一起流动
    float2 p = uv + 1.8 * r;

    // 浓度：只轻微影响亮度和透明度
    float density = fbm(p) * 0.5 + 0.5;
    float d = smoothstep(0.28, 0.72, density);

    // 每种颜色一个独立噪声场，各自以不同速度、不同轨迹缓慢漂移
    float logits[COLOR_N];
    float maxl = -1e9;
    [unroll]
    for (int k = 0; k < COLOR_N; k++) {
        float fk = (float)k;
        float2 drift = float2(
            sin(t * (0.07 + 0.011 * fk) + fk * 2.1),
            cos(t * (0.06 + 0.013 * fk) + fk * 1.3)) * 1.1;
        float n = grad_noise(p * COLOR_SCALE + drift + fk * float2(7.31, 3.77));
        logits[k] = (n + BIAS[k]) * SHARP;
        maxl = max(maxl, logits[k]);
    }

    // 软选择：强者占主导，边界处才发生混合
    float3 acc = float3(0.0, 0.0, 0.0);
    float wsum = 0.0;
    [unroll]
    for (int j = 0; j < COLOR_N; j++) {
        float w = exp(logits[j] - maxl);
        acc += w * COLORS[j];
        wsum += w;
    }
    float3 base = acc / wsum;

    // 轻微提高饱和度，抵消混合带来的发灰
    float luma = dot(base, float3(0.299, 0.587, 0.114));
    base = lerp(float3(luma, luma, luma), base, 1.2);

    // 浓处明亮、薄处稍暗，但仍保持颜色干净
    float3 color = base * lerp(0.78, 1.05, d);

    float alpha = lerp(0.72, 1.0, d);

    // 缓慢呼吸，暗示任务仍在进行
    alpha *= 0.94 + 0.06 * sin(t * 1.3);

    return float4(saturate(color), saturate(alpha));
}