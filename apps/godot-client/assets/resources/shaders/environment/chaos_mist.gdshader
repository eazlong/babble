shader_type canvas_item;

// 混沌之雾 — 用于「混乱/失序」状态的氛围遮罩。
// 用法：挂在覆盖全屏的 ColorRect 上，COLOR 的 alpha 即遮罩强度。
uniform float speed : hint_range(0.0, 2.0) = 0.3;
uniform float intensity : hint_range(0.0, 1.0) = 0.5;
uniform vec4 mist_color : source_color = vec4(0.70, 0.78, 0.78, 0.30);
uniform float scale : hint_range(0.5, 8.0) = 3.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * scale;
	// 两层反向漂移的噪声叠加，避免出现明显的平铺节奏。
	float n = noise(uv + TIME * speed) * 0.6
	        + noise(uv * 2.0 - TIME * speed * 1.4) * 0.4;
	COLOR = vec4(mist_color.rgb, mist_color.a * n * intensity * COLOR.a);
}
