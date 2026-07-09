## transition_wipe.gdshader
## 场景切换过渡效果 — UV wipe + 径向扩散
## Godot 4.6, canvas_item shader
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wipe_direction = vec2(1.0, 0.0);
uniform vec4 wipe_color : source_color = vec4(0.2, 0.2, 0.3, 1.0);
uniform bool radial_mode = false;
uniform float smoothness : hint_range(0.0, 0.2) = 0.05;

void fragment() {
    float wipe_threshold;

    if (radial_mode) {
        vec2 center = vec2(0.5, 0.5);
        float dist = distance(UV, center);
        wipe_threshold = dist / 0.5;
    } else {
        vec2 normalized_dir = normalize(wipe_direction);
        vec2 uv_offset = UV - vec2(0.5, 0.5);
        wipe_threshold = dot(uv_offset + vec2(0.5, 0.5), normalized_dir);
    }

    float wipe_edge = smoothstep(progress - smoothness, progress, wipe_threshold);

    vec4 screen_color = texture(TEXTURE, UV);

    COLOR = mix(wipe_color, screen_color, wipe_edge);
}
