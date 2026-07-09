## spirit_glow.gdshader
## 词灵发光效果 — 边缘发光 + 脉冲动画
## Godot 4.6, canvas_item shader
shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.4, 1.0);
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.0;
uniform float rim_width : hint_range(0.0, 0.5) = 0.2;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);

    vec4 tex_color = texture(TEXTURE, UV);

    float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
    float pulse_multiplier = 0.7 + pulse * 0.3;

    float rim = smoothstep(0.5 - rim_width, 0.5, dist);
    rim *= smoothstep(0.5, 0.5 + rim_width * 0.5, dist);
    rim = 1.0 - rim;

    float glow_alpha = rim * glow_intensity * pulse_multiplier * glow_color.a;

    vec3 final_rgb = mix(tex_color.rgb, glow_color.rgb, rim * 0.6 * glow_intensity * pulse_multiplier);

    COLOR = vec4(final_rgb, max(tex_color.a, glow_alpha));
}

void vertex() {
    float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
    float scale = 1.0 + pulse * 0.05 * glow_intensity;
    VERTEX *= scale;
}
