// 编号 9：水晶球折射
// 在画面中央放一颗玻璃球：球内显示倒立、放大的折射画面，
// 再叠加球面高光、边缘全反射和下方投影。

[vk::binding(0, 2)]
Sampler2D g_BackgroundTex;

struct PS_INPUT
{
    float4 Pos : SV_POSITION;
    float2 UV  : TEXCOORD0;
};

float2 aspect_scale(float2 uv)
{
    float dx = max(abs(ddx(uv.x)), 1e-6f);
    float dy = max(abs(ddy(uv.y)), 1e-6f);
    float aspect = clamp(dy / dx, 0.1f, 10.0f);
    return (aspect >= 1.0f) ? float2(aspect, 1.0f)
                           : float2(1.0f, 1.0f / aspect);
}

[shader("fragment")]
float4 main(PS_INPUT input) : SV_TARGET
{
    float2 uv = saturate(input.UV);
    float2 scale = aspect_scale(uv);
    float2 p = (uv - 0.5f) * scale;
    float r = length(p);

    // 取画面宽高中较短的一边作为球的直径，并留出 4% 边距。
    // 这样球会尽可能大，同时完整落在窗口内，不会被上下或左右裁掉。
    float aspect = scale.x / scale.y;
    float R = 0.48f * min(1.0f, aspect);

    // 球内折射：越靠近边缘，采样点偏移越大，形成鱼眼般的倒立像
    float rr = saturate(r / R);
    float lens_scale = 0.60f + 0.40f * rr * rr;
    float2 lens_p = -p * lens_scale;

    // 三通道使用略微不同的折射率
    float2 uv_r = saturate(0.5f + lens_p * 0.985f / scale);
    float2 uv_g = saturate(0.5f + lens_p / scale);
    float2 uv_b = saturate(0.5f + lens_p * 1.015f / scale);

    float4 sr = g_BackgroundTex.Sample(uv_r);
    float4 sg = g_BackgroundTex.Sample(uv_g);
    float4 sb = g_BackgroundTex.Sample(uv_b);

    float sphere_a = sg.a;
    float3 sphere = float3(
        sr.r / max(sr.a, 1e-4f),
        sg.g / max(sg.a, 1e-4f),
        sb.b / max(sb.a, 1e-4f));

    // 玻璃的冷色倾向
    sphere = lerp(sphere, sphere * float3(0.85f, 0.95f, 1.10f), 0.18f);

    // 球面法线与方向光，给出立体明暗
    float3 n = float3(p / R, sqrt(saturate(1.0f - rr * rr)));
    float3 light_dir = normalize(float3(-0.55f, -0.60f, 0.60f));
    float3 half_dir = normalize(light_dir + float3(0.0f, 0.0f, 1.0f));

    float diff = saturate(dot(n, light_dir));
    float spec = pow(saturate(dot(n, half_dir)), 70.0f);

    sphere *= 0.70f + 0.45f * diff;
    sphere += float3(1.0f, 1.0f, 1.0f) * spec * 0.9f;

    // 边缘全反射亮圈
    float rim = smoothstep(0.86f, 0.995f, rr);
    sphere += float3(0.55f, 0.85f, 1.00f) * rim * 0.35f;

    // 左上角的锐利高光，位置和大小都随球半径缩放
    float2 hl = p - float2(-0.40f, -0.47f) * R;
    float hl_radius = max(0.11f * R, 1e-4f);
    sphere += float3(1.0f, 1.0f, 1.0f) * exp(-dot(hl, hl) / (hl_radius * hl_radius)) * 0.90f;

    // 背景与投影
    float4 bg = g_BackgroundTex.Sample(uv);
    float2 shadow_p = p - float2(0.15f, 0.25f) * R;
    float shadow = 1.0f - smoothstep(R * 0.85f, R * 1.10f, length(shadow_p));
    bg.rgb *= 1.0f - 0.18f * shadow;

    // 球体边缘抗锯齿后与背景混合
    float inside = 1.0f - smoothstep(R - 0.003f, R + 0.003f, r);
    float3 rgb = lerp(bg.rgb, sphere * sphere_a, inside);
    float alpha = lerp(bg.a, sphere_a, inside);

    // 预乘 Alpha 要求颜色不超过 Alpha
    rgb = min(rgb, float3(alpha, alpha, alpha));

    return float4(saturate(rgb), saturate(alpha));
}
