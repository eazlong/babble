// ambient_particle.gdshader
// 环境漂浮粒子效果 — 柔和发光 + 轻微波动
// Godot 4.6, canvas_item shader
// 复杂度: 低
// 性能预算: 1ms/帧

shader_type canvas_item;
render_mode blend_add;

// ============================================================
// Uniform变量声明
// ============================================================

// 颜色参数
uniform vec4 particle_color : source_color = vec4(0.9, 0.95, 1.0, 0.5);

// 强度参数
uniform float glow_intensity : hint_range(0.0, 1.5) = 0.8;

// 尺寸参数
uniform float particle_size : hint_range(0.1, 0.5) = 0.2;

// 时间参数
uniform float wave_speed : hint_range(0.0, 2.0) = 0.5;

// 开关参数
uniform bool enable_glow = true;
uniform bool enable_wave = true;

// ============================================================
// Fragment函数
// ============================================================

void fragment() {
    vec2 uv = UV;

    // 基础纹理采样
    vec4 tex_color = texture(TEXTURE, UV);

    // 计算粒子中心距离
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);

    // 发光效果 (中心亮，边缘暗)
    float glow = 1.0 - smoothstep(0.0, particle_size, dist);
    if (enable_glow) {
        glow *= glow_intensity;
    } else {
        glow = 0.0;
    }

    // 波动效果 (时间驱动)
    float wave = 1.0;
    if (enable_wave) {
        wave = sin(TIME * wave_speed) * 0.3 + 0.7;  // 0.7-1.0范围波动
    }

    // 组合效果
    vec3 final_rgb = tex_color.rgb + particle_color.rgb * glow * wave;
    float final_alpha = tex_color.a * (1.0 + glow * wave * particle_color.a);

    // Alpha裁剪
    final_alpha = clamp(final_alpha, 0.0, 1.0);

    COLOR = vec4(final_rgb, final_alpha);
}