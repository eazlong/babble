// wake_eye_open.gdshader
// 睁眼过场 — 全屏黑色遮罩上**两只眼睛**依次睁开（每只眼 = 上睑 + 下睑两片），露出世界。
// Godot 4.6, canvas_item shader
// 复杂度: 低 (仅 fragment，每只眼两次 pow + 两次 smoothstep)
// 性能预算: 1.0ms/帧 (全屏)
//
// 用法：把本 shader 设到一个全屏黑色 ColorRect 的 material 上
// （`WakeEyeTransition` 组件负责建它并驱动参数）。
//
// ── 形状模型：两只眼睛，每只两片眼睑 ─────────────────────────────
//
// 左眼与右眼各自是一条独立的"眼形"开口，**中间留出鼻梁**（两条开口不连在一起，
// 连起来就又读成一个形状了）：
//
//        ╭───╮            ╭───╮
//       ╱     ╲          ╱     ╲        左眼中心 eye_center_left
//      │  左眼  │  鼻梁  │  右眼  │      右眼中心 eye_center_right
//       ╲     ╱          ╲     ╱
//        ╰───╯            ╰───╯
//
// 单只眼睛由 `eye_shading()` 算：上、下眼睑各是一条**边缘曲线**（在眼角交汇），
// 曲线在眼睛中央到达 `lid_upper_y` / `lid_lower_y`，到眼角收拢到 `lid_corner_y`。
// 两片眼睑除了位置不同，还有各自的弧度（上睑拱、下睑浅），所以睁到一半是杏仁形。
//
// 两只眼的位置/弧度都一样，只有**相位**略有差别（右眼慢一点，见组件的
// `lid_*_right_at()`）——两只眼完全同步会显得像机械开合。
//
// ⚠️ 注释只能用 `//`。Godot 4 把 `#` 开头当**预处理指令**（#define / #include / …），
//    写成 `# 注释` 会让整份 shader **静默编译失败**：材质还在、set_shader_parameter()
//    也不报错，但画面完全不响应 —— 这个过场因此变成过"一帧静止黑图"。
//    `test/core/test_shader_sources.gd` 会扫全项目的 shader 挡住这类回归。

shader_type canvas_item;

// 左/右眼中心的横向位置（UV，0~1）。
uniform float eye_center_left : hint_range(0.0, 1.0) = 0.26;
uniform float eye_center_right : hint_range(0.0, 1.0) = 0.74;

// 单只眼睛的水平半宽（UV）。**必须小于两只眼的中心间距的一半**，否则两只眼会连成一片。
uniform float eye_half_width : hint_range(0.02, 0.4) = 0.22;

// 眼角轮廓指数。**这是"眼睛"和"眼镜片"的分界**：
// 横向 profile = (1 - sx²)^eye_profile_power，sx = (x - 眼心) / 半宽。
//   = 1.0 → 抛物线。眼角（|sx| = 1）处斜率**有限**，上下两条眼睑边缘以非零夹角相交
//           → 两端是**尖的**（参考图那种眼形：两端尖、中间大）。
//   < 1.0 → 越接近圆角矩形：眼角切线趋近竖直，两端被磨圆，看起来像**眼镜片**。
// 早期版本用的超椭圆 (1 - |sx|^n)^(1/n)（n = 2.6）就是后者，用户反馈"像眼镜、要两端尖"。
uniform float eye_profile_power : hint_range(0.6, 2.0) = 1.0;

// 两片眼睑各自的弧度指数（作用在 profile 上）。默认都取 1.0 = 用同一条抛物线，
// 形状差异交给**振幅**：上睑抬得比下睑落得多（组件里的 LID_UPPER_OPEN_Y / LID_LOWER_OPEN_Y）。
// 两条振幅不同的弧才会在眼角交出尖角 —— 参考图里上眼睑是一道大弧、下眼睑浅得多。
uniform float lid_arch_upper : hint_range(0.3, 3.0) = 1.0;

uniform float lid_arch_lower : hint_range(0.3, 3.0) = 1.0;

// ── 左眼的两片眼睑（在眼睛中央的 y，UV，1 = 屏幕底）─────────────────
// 上睑 == 下睑 == 眼角线时完全闭合（缝隙 0 → 全黑）。
uniform float lid_upper_y = 0.54;
uniform float lid_lower_y = 0.54;
uniform float lid_corner_y = 0.54;

// ── 右眼的两片眼睑 ───────────────────────────────────────────────
uniform float lid_upper_y_right = 0.54;
uniform float lid_lower_y_right = 0.54;
uniform float lid_corner_y_right = 0.54;

// 边缘羽化量（柔化眼睑边缘），UV 高度。
uniform float eye_feather : hint_range(0.001, 0.05) = 0.006;

// 眼睑/黑暗颜色（黑色）。
uniform vec4 lid_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// 眼眶阴影：贴着眼睑边缘的一圈压暗多少（0 = 无）。用半透明黑实现，
// 所以是"把后面的世界压暗"而不是画一圈灰边。
uniform float lid_shade : hint_range(0.0, 1.0) = 0.6;

// 眼眶阴影向眼内延伸的宽度（UV 高度）。
uniform float lid_shade_width : hint_range(0.01, 0.4) = 0.10;

// 整层透明度（由组件在睁眼结束后淡出，彻底露出世界；避免依赖 modulate 与 shader 的交互）。
uniform float overlay_alpha : hint_range(0.0, 1.0) = 1.0;

// 单只眼睛：返回 vec2(缝隙内权重, 眼眶阴影权重)。
// 缝隙内权重 1 = 露出世界，0 = 眼睑（黑）。
vec2 eye_shading(vec2 uv, float center_x, float upper_y, float lower_y, float corner_y) {
	// 横向 profile：眼睛中央为 1，到眼角（|sx| >= 1）降到 0 → 两片眼睑在眼角收拢成眼形。
	float sx = abs((uv.x - center_x) / eye_half_width);
	// 抛物线（1 - sx²）：眼角斜率有限 → 两端是**尖的**。
	// 换成超椭圆 (1 - |sx|^n)^(1/n) 会把两端磨圆，整只眼就变成眼镜片。
	float profile = pow(max(0.0, 1.0 - sx * sx), eye_profile_power);

	// 两片眼睑各自的边缘曲线（弧度不同 → 睁到一半是杏仁，不是对称橄榄）。
	float upper_edge = mix(corner_y, upper_y, pow(profile, lid_arch_upper));
	float lower_edge = mix(corner_y, lower_y, pow(profile, lid_arch_lower));

	// 上睑之下、下睑之上 = 缝隙（露出世界）；带羽化。
	float inside_upper = smoothstep(upper_edge - eye_feather, upper_edge + eye_feather, uv.y);
	float inside_lower = 1.0 - smoothstep(lower_edge - eye_feather, lower_edge + eye_feather, uv.y);
	float inside = inside_upper * inside_lower;

	// 眼眶阴影：贴着每条眼睑边缘最强，向眼内衰减。
	float rim_upper = 1.0 - smoothstep(0.0, lid_shade_width, uv.y - upper_edge);
	float rim_lower = 1.0 - smoothstep(0.0, lid_shade_width, lower_edge - uv.y);
	return vec2(inside, max(rim_upper, rim_lower) * inside);
}

void fragment() {
	vec2 left_eye = eye_shading(UV, eye_center_left, lid_upper_y, lid_lower_y, lid_corner_y);
	vec2 right_eye = eye_shading(UV, eye_center_right, lid_upper_y_right, lid_lower_y_right, lid_corner_y_right);

	// 两只眼取并集：中间鼻梁落在两者之外 → 保持眼睑（黑）。
	float inside = max(left_eye.x, right_eye.x);
	float rim = max(left_eye.y, right_eye.y);

	// 缝隙外：不透明眼睑；缝隙内：透明（露出世界）+ 贴边那圈半透明黑。
	float alpha = (mix(lid_color.a, 0.0, inside) + lid_shade * rim) * overlay_alpha;
	COLOR = vec4(lid_color.rgb, clamp(alpha, 0.0, 1.0));
}
