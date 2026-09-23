// world_brightness.gdshader
// 场景提亮 — 把归卷厅这种偏暗的场景整体抬高，不改美术资源本身。
// Godot 4.6, canvas_item shader
// 复杂度: 低 (仅 fragment，一次屏幕采样 + 一次 pow)
// 性能预算: ~0.6ms/帧 (全屏, 单次 backbuffer 采样)
//
// 用法：把本 shader 设到一个**全屏 ColorRect** 的 material 上，该 ColorRect 放在
// **场景内容之上、所有 UI 之下**的 CanvasLayer 里（本场景是 layer 5：世界美术是 -50，
// 腓腓在默认画布 0，HUD 10 / dialogue 20 / overlay 30 / mic 90 都在它上面）。
// 这样只提亮场景，不动对话框、任务条、录音石这些本来就够亮的 UI。
//
// ── 两个已经踩过的坑，改这个文件前先读 ────────────────────────────────
//
// 1) **注释只能用 `//`，不能用 `#`**。Godot 4 的 shader 语言把 `#` 当预处理指令
//    （`#define` / `#include` / `#ifdef` …），`## foo` 不是合法指令，整个 shader
//    会**静默**编译失败：`Shader.get_shader_uniform_list()` 返回空，
//    材质退化成默认材质 → 全屏 ColorRect 直接画出它的 `color`（不透明白）。
//    症状是"屏幕全白 / 参数怎么改都没反应"，而且不一定有明显报错。
//    （`wake_eye_open.gdshader` 目前就是这个状态，见 docs/asset-manifest.md。）
//
// 2) 取样屏幕纹理要配 `BackBufferCopy`（`COPY_MODE_VIEWPORT`），并且它必须和
//    ColorRect 在**同一个 CanvasLayer 里排在前面**。少了它，`screen_tex` 采到的是
//    本帧自己刚写回去的内容 → 逐帧自乘的反馈回路：gamma 会指数级往 1 收敛，
//    几帧内整屏烧成纯白（不是"太亮"，是坏掉）。
//
// 为什么用 gamma 而不是乘一个系数：
// 这类"整体偏暗"的场景里，压得最狠的是**暗部**（归卷厅实测 62% 的像素低于 40/255）。
// 纯乘法（CanvasModulate / modulate > 1）对 0.03 这种暗部几乎无效（×1.5 只到 0.045），
// 只会把本来就亮的地方推到过曝。`pow(c, 1/gamma)` 是抬暗部、留高光的曲线：
// gamma=1.5 时 8/255 → 26，43/255 → 78，101/255 → 138。
//
// gain 是曲线之后的整体增益，默认 1.0（不动）。实测 1.05 就把高光顶到接近过曝
// （通道 ≥250 的像素 1.6% → 2.1%），暗部却几乎没多抬——所以默认留在 1.0，
// 只在确实想整体再推一点时才调大。
// lift 是纯加法，需要"发灰的空气感"时才开，默认 0（加法会把黑位抬起来，画面会发雾）。

shader_type canvas_item;
render_mode unshaded;

// 屏幕内容（backbuffer）。Godot 4 会为本 uniform 自动插入一次 backbuffer 拷贝，
// 但 2D 下仍需要场景里有一个 BackBufferCopy 节点来决定拷贝时机（见上文坑 2）。
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

// 提亮曲线强度：1.0 = 原样，越大暗部抬得越多。1.4~1.7 是"明显变亮但不发灰"的区间。
uniform float gamma_lift : hint_range(1.0, 3.0) = 1.5;

// 曲线之后的整体增益。
uniform float gain : hint_range(0.5, 2.0) = 1.0;

// 纯加法抬黑位。默认 0：加法会让画面发雾，只在确实想要空气感时才调大。
uniform float lift : hint_range(0.0, 0.3) = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	c = pow(clamp(c, 0.0, 1.0), vec3(1.0 / gamma_lift));
	c = c * gain + lift;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
