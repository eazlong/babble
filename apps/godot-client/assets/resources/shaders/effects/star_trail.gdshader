// star_trail.gdshader
// 星星拖尾效果 — UV轨迹 + 尾迹淡出
// Godot 4.6, canvas_item shader
// 复杂度: 中等
// 性能预算: 2ms/帧

shader_type canvas_item;
render_mode blend_add;

// ============================================================
// Uniform变量声明
// ============================================================

// 颜色参数
uniform vec4 trail_color : source_color = vec4(1.0, 0.9, 0.3, 1.0);

// 强度参数
uniform float trail_intensity : hint_range(0.0, 2.0) = 1.0;

// 尺寸参数
uniform float trail_length : hint_range(0.1, 0.5) = 0.3;
uniform float trail_width : hint_range(0.01, 0.1) = 0.05;

// 时间参数
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float speed : hint_range(0.0, 5.0) = 2.0;

// 开关参数
uniform bool enable_trail = true;

// ============================================================
// 常量定义
// ============================================================

const float PI = 3.14159265359;
const vec2 CENTER = vec2(0.5, 0.5);

// ============================================================
// 辅助函数
// ============================================================

// 二次贝塞尔曲线 (星星飞行路径)
vec2 bezier_path(float t) {
    // 抛物线轨迹：向上弧形
    vec2 p0 = vec2(0.0, 0.5);   // 起点
    vec2 p1 = vec2(0.5, 0.0);   // 控制点（抛物线顶点）
    vec2 p2 = vec2(1.0, 0.5);   // 终点

    float u = 1.0 - t;
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2;
}

// ============================================================
// Fragment函数
// ============================================================

void fragment() {
    vec2 uv = UV;

    // 基础纹理采样
    vec4 tex_color = texture(TEXTURE, UV);

    if (!enable_trail) {
        COLOR = tex_color;
        return;
    }

    // 计算当前星星位置 (基于progress)
    vec2 star_pos = bezier_path(progress);

    // 计算拖尾路径
    // 拖尾从progress开始向后延伸trail_length
    float trail_start = progress - trail_length;
    float trail_end = progress;

    // 检查当前UV是否在拖尾范围内
    float in_trail = 0.0;

    for (float t = trail_start; t <= trail_end; t += 0.01) {
        vec2 trail_point = bezier_path(t);
        float dist = distance(uv, trail_point);

        // 拖尾宽度随距离递减
        float width_factor = (t - trail_start) / trail_length;
        float current_width = trail_width * (1.0 - width_factor * 0.7);

        if (dist < current_width) {
            in_trail = max(in_trail, 1.0 - width_factor);
        }
    }

    // 计算星星头部亮度
    float dist_to_star = distance(uv, star_pos);
    float star_brightness = 1.0 - smoothstep(0.0, 0.05, dist_to_star);

    // 组合效果
    vec3 final_rgb = tex_color.rgb + trail_color.rgb * (in_trail * trail_intensity + star_brightness * 2.0);
    float final_alpha = tex_color.a + in_trail * trail_intensity * trail_color.a + star_brightness;

    // Alpha裁剪
    final_alpha = clamp(final_alpha, 0.0, 1.0);

    COLOR = vec4(final_rgb, final_alpha);
}