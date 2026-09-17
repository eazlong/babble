## wake_eye_open.gdshader
## 睁眼过场 — 在全屏黑色遮罩上开出一个宽圆角“眼睛”窗口；眼睛睁开时窗口垂直张开，露出世界。
## Godot 4.6, canvas_item shader
## 复杂度: 低 (仅 fragment，一次超椭圆计算)
## 性能预算: 1.0ms/帧 (全屏)
##
## 用法：把本 shader 设到一个全屏黑色 ColorRect 的 material 上。
##  - eye_open = 0.0 : 眼睛几乎闭合，只露出一条水平细缝（参考帧1）。
##  - eye_open = 1.0 : 眼睛全开，窗口近乎铺满屏幕，仅保留圆角黑边（参考帧3）。
## 随后由控制器对 overlay_alpha 做淡出，彻底露出世界。

shader_type canvas_item;

# ============================================================
# Uniform 变量声明
# ============================================================

# 眼睛张开的程度（0 = 闭合，1 = 全开）
uniform float eye_open : hint_range(0.0, 1.0) = 0.0;

# 窗口中心（UV 空间，0~1）
uniform vec2 eye_center = vec2(0.5, 0.5);

# 窗口水平半宽（略大于 0.5，使窗口横向铺满屏幕）
uniform float eye_half_width = 0.54;

# 闭合时窗口的半高（一条细缝）
uniform float eye_half_height_closed = 0.05;

# 全开时窗口的半高（纵向铺满屏幕中心）
uniform float eye_half_height_open = 0.50;

# 超椭圆指数：2 = 椭圆，趋近高值 = 圆角矩形；取 2.6 得到柔和“眼部/镜头”形状
uniform float eye_shape_power : hint_range(1.5, 6.0) = 2.6;

# 边缘羽化量（柔化眼睑边缘）
uniform float eye_feather : hint_range(0.001, 0.2) = 0.04;

# 眼睑/黑暗颜色（黑色）
uniform vec4 lid_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

# 整层透明度（由控制器在眼睛全开后淡出，彻底露出世界；避免依赖 modulate 与 shader 的交互）
uniform float overlay_alpha : hint_range(0.0, 1.0) = 1.0;

# ============================================================
# Fragment 函数
# ============================================================

void fragment() {
	# 垂直半高随 eye_open 从闭合细缝插值到全开
	float half_height = mix(eye_half_height_closed, eye_half_height_open, eye_open);

	# 把 UV 归一化到以窗口中心为原点、以半宽/半高为半径的坐标系
	vec2 offset = UV - eye_center;
	vec2 scaled = vec2(offset.x / eye_half_width, offset.y / half_height);

	# 超椭圆归一化距离（移动端友好的简单 pow）
	float n = eye_shape_power;
	float superellipse = pow(pow(abs(scaled.x), n) + pow(abs(scaled.y), n), 1.0 / n);

	# 窗口内 <=> superellipse < 1；用羽化半径做柔和边缘
	float inside = 1.0 - smoothstep(1.0 - eye_feather, 1.0 + eye_feather, superellipse);

	# 窗口内为透明（露出世界），窗口外为黑色眼睑；乘以整层透明度
	float alpha = mix(lid_color.a, 0.0, inside) * overlay_alpha;
	COLOR = vec4(lid_color.rgb, alpha);
}
