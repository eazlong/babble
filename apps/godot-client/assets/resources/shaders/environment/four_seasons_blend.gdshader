shader_type canvas_item;

// 四季同街 — 幕 5 的「一街四季」过渡。
// 把画面沿 UV.x 分成四段（冬/春/夏/秋），再按 transition 把整体推向秋季一侧，
// 形成一条可见的、随时间推进的季节分界线。
uniform float transition : hint_range(0.0, 1.0) = 0.0;
uniform vec4 winter_tint : source_color = vec4(0.85, 0.90, 1.00, 1.0);
uniform vec4 spring_tint : source_color = vec4(1.00, 0.88, 0.92, 1.0);
uniform vec4 summer_tint : source_color = vec4(0.80, 1.00, 0.85, 1.0);
uniform vec4 autumn_tint : source_color = vec4(1.00, 0.90, 0.70, 1.0);
uniform float edge_softness : hint_range(0.02, 0.5) = 0.15;

void fragment() {
	float x = UV.x;

	// 四段色带：x<0.25 冬、<0.5 春、<0.75 夏、否则 秋。
	vec4 section = mix(
		mix(winter_tint, spring_tint, step(0.25, x)),
		mix(summer_tint, autumn_tint, step(0.75, x)),
		step(0.5, x)
	);

	// transition 推进时，分界线由左向右扫过，末端收敛到秋色。
	float k = smoothstep(x - edge_softness, x + edge_softness, transition * 1.25);
	COLOR = COLOR * mix(section, autumn_tint, k);
}
