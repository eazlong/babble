class_name SpellingSlotBar
extends Control

## 拼写槽位条（GDD §4.5）—— 场景里那个"输入框"。
##
## 为什么独立成组件：这是本场景**唯一一个持续随时间变化的 UI 面板**——空槽待机呼吸、
## 填入时该格弹入并亮一圈光晕，两种动画都要逐帧推进。塞进场景控制器会和字母精灵的
## 演出代码搅在一起（那里已经在管飞行、散落、刻印三条时序了）。
##
## 槽位数 = **目标单词长度**（2026-09-22 决定）：开局就摆出 N 个空槽，孩子能看出这个
## 单词要拼几个字母。目标词未知时回退成"已拼字母数"（旧行为），这样没取到词牌时
## 槽位条依然能用、也不会因为一个空 `current_word` 就整条消失。
##
## 字形仍然交给子 Label 画（不自己 `draw_string`）：字号、中文字体回退、主题覆盖
## 这些都已经在 Label 上配好了，自己画等于把这些重写一遍。组件只负责**格子**：
## 底板、描边呼吸、落位光晕。

## 槽位尺寸与间隔，必须与控制器 `_slot_center()` 的换算一致（48 宽 + 12 间隔）。
const CELL_SIZE: Vector2 = Vector2(48, 60)
const CELL_SEPARATION: float = 12.0
## 格数上限。这是**版面**约束不是玩法约束：槽框宽 600，一格 48 + 12 间隔，
## 10 格 = 10*48 + 9*12 = 588 刚好排得下；11 格就 648 溢出。
## 词库里最长的目标词是 8 个字母（BUILDING / COUNTRY），但玩家可能**多说**字母，
## 那些字母必须看得见，否则他没法判断该 "undo" 掉哪个。
const MAX_CELLS: int = 10
const CORNER_RADIUS: int = 10

const COLOR_CELL_BG_EMPTY: Color = Color(0.06, 0.07, 0.12, 0.55)
const COLOR_CELL_BG_FILLED: Color = Color(0.22, 0.17, 0.07, 0.78)
const COLOR_RIM_EMPTY: Color = Color(0.66, 0.58, 0.36, 1.0)
const COLOR_RIM_FILLED: Color = Color(1.00, 0.85, 0.40, 1.0)
const COLOR_GLOW: Color = Color(1.00, 0.90, 0.52, 1.0)
const COLOR_GLYPH: Color = Color(0.90, 0.85, 0.50, 1.0)
const COLOR_GLYPH_FILLED: Color = Color(1.00, 0.97, 0.76, 1.0)

## 空格待机呼吸：周期 + 相邻格相位差。错开相位是为了让呼吸**像一波推过去**，
## 而不是整排同时明暗（同时闪会读成"报错闪烁"，不是"在等你"）。
const BREATH_PERIOD_S: float = 2.6
const BREATH_PHASE_STEP: float = 0.55
const BREATH_MIN_ALPHA: float = 0.34
const BREATH_MAX_ALPHA: float = 0.80

## 单格落位光晕时长（秒）。
const LAND_DURATION_S: float = 0.52
## 字形弹入的过冲幅度与回落时长。
const LAND_POP_SCALE: float = 1.28
const LAND_POP_SETTLE_S: float = 0.24

## 槽位格数。设置即重建字形 Label。
var cell_count: int = 0:
	set(value):
		var clamped: int = clampi(value, 0, MAX_CELLS)
		if clamped == cell_count and not _glyphs.is_empty():
			return
		cell_count = clamped
		_rebuild_glyphs()

var _glyphs: Array[Label] = []
## 每格是否已填（填了就不再呼吸，稳定亮着 = "这格定了"）。
var _filled: PackedByteArray = PackedByteArray()
## 每格的落位光晕进度：1 → 0，<0 表示空闲。
var _land: PackedFloat32Array = PackedFloat32Array()
var _t: float = 0.0
var _style_empty: StyleBoxFlat
var _style_filled: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_styles()
	_rebuild_glyphs()
	_layout_glyphs()


func _ensure_styles() -> void:
	if _style_empty == null:
		_style_empty = StyleBoxFlat.new()
		_style_empty.bg_color = COLOR_CELL_BG_EMPTY
		_style_empty.set_border_width_all(2)
		_style_empty.set_corner_radius_all(CORNER_RADIUS)
	if _style_filled == null:
		_style_filled = StyleBoxFlat.new()
		_style_filled.bg_color = COLOR_CELL_BG_FILLED
		_style_filled.set_border_width_all(2)
		_style_filled.set_corner_radius_all(CORNER_RADIUS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_glyphs()
		queue_redraw()


# ── 对外接口 ────────────────────────────────────────────────────────

## 第 index 格的**局部中心**。控制器靠它算精灵的飞行落点，所以必须和画面一致。
func get_cell_center(index: int) -> Vector2:
	# cell_count 为 0 时按"1 格居中"排版：间距仍然对，不会退化成贴左边。
	var count: int = maxi(cell_count, 1)
	var total: float = float(count) * CELL_SIZE.x + float(count - 1) * CELL_SEPARATION
	var left: float = (size.x - total) * 0.5
	return Vector2(
		left + float(index) * (CELL_SIZE.x + CELL_SEPARATION) + CELL_SIZE.x * 0.5,
		size.y * 0.5
	)


## 取第 index 格的字形 Label（控制器把它挂进 `slot_labels` 供既有逻辑读写）。
func get_glyph_label(index: int) -> Label:
	if index < 0 or index >= _glyphs.size():
		return null
	return _glyphs[index]


func get_glyph_labels() -> Array[Label]:
	return _glyphs


## 设置某格字形。空串 = 该格回到空槽（继续呼吸）。
func set_glyph(index: int, text: String) -> void:
	if index < 0 or index >= _glyphs.size():
		return
	var glyph: Label = _glyphs[index]
	glyph.text = text
	glyph.scale = Vector2.ONE
	glyph.add_theme_color_override("font_color", COLOR_GLYPH)
	_filled[index] = 0 if text.is_empty() else 1
	queue_redraw()


func clear_glyphs() -> void:
	for i in range(_glyphs.size()):
		set_glyph(i, "")


func is_cell_filled(index: int) -> bool:
	if index < 0 or index >= _filled.size():
		return false
	return _filled[index] != 0


## 空槽描边当前的呼吸透明度。抽成方法是为了让测试能直接量呼吸，
## 而不用去截屏比较像素。
func _empty_rim_alpha(index: int) -> float:
	var phase: float = TAU * (_t / BREATH_PERIOD_S) - float(index) * BREATH_PHASE_STEP
	return lerpf(BREATH_MIN_ALPHA, BREATH_MAX_ALPHA, sin(phase) * 0.5 + 0.5)


## 第 index 格落位光晕的剩余进度（1 → 0）。给测试与调试用。
func get_land_progress(index: int) -> float:
	if index < 0 or index >= _land.size():
		return 0.0
	return _land[index]


## 填入演出：该格亮一圈向外扩散的光晕 + 字形弹入。
## 由控制器在"精灵落位"和"刻印逐字点亮"两处调用。
func play_land(index: int) -> void:
	if index < 0 or index >= cell_count:
		return
	if index < _land.size():
		_land[index] = 1.0
	if index < _glyphs.size():
		var glyph: Label = _glyphs[index]
		glyph.pivot_offset = CELL_SIZE * 0.5
		glyph.add_theme_color_override("font_color", COLOR_GLYPH_FILLED)
		glyph.scale = Vector2(LAND_POP_SCALE, LAND_POP_SCALE)
		if glyph.is_inside_tree():
			var tween: Tween = glyph.create_tween()
			tween.tween_property(glyph, "scale", Vector2.ONE, LAND_POP_SETTLE_S) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			glyph.scale = Vector2.ONE
	queue_redraw()


func is_animating() -> bool:
	if cell_count == 0:
		return false
	for value in _land:
		if value > 0.0:
			return true
	# 空格一直在呼吸，所以只要还有空格就算在动
	for i in range(cell_count):
		if not is_cell_filled(i):
			return true
	return false


# ── 内部 ────────────────────────────────────────────────────────────

func _rebuild_glyphs() -> void:
	for glyph in _glyphs:
		if is_instance_valid(glyph):
			glyph.queue_free()
	_glyphs.clear()
	for i in range(cell_count):
		var glyph := Label.new()
		glyph.name = "SlotGlyph%d" % i
		glyph.custom_minimum_size = CELL_SIZE
		glyph.size = CELL_SIZE
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 40)
		glyph.add_theme_color_override("font_color", COLOR_GLYPH)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glyph)
		_glyphs.append(glyph)
	_filled.resize(cell_count)
	_filled.fill(0)
	_land.resize(cell_count)
	for i in range(_land.size()):
		_land[i] = 0.0
	_layout_glyphs()
	queue_redraw()


func _layout_glyphs() -> void:
	for i in range(_glyphs.size()):
		var glyph: Label = _glyphs[i]
		glyph.size = CELL_SIZE
		glyph.position = get_cell_center(i) - CELL_SIZE * 0.5
		glyph.pivot_offset = CELL_SIZE * 0.5


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var still: bool = false
	for i in range(_land.size()):
		if _land[i] > 0.0:
			_land[i] = maxf(_land[i] - delta / LAND_DURATION_S, 0.0)
			still = true
	# 呼吸本身就是持续动画，所以只要有空格就得每帧重画。
	# 代价：≤8 个 StyleBoxFlat + 几条 arc，只有一个这样的控件。
	if still or cell_count > 0:
		queue_redraw()


func _draw() -> void:
	_ensure_styles()
	for i in range(cell_count):
		var center: Vector2 = get_cell_center(i)
		var rect: Rect2 = Rect2(center - CELL_SIZE * 0.5, CELL_SIZE)
		var land: float = _land[i] if i < _land.size() else 0.0
		var filled: bool = is_cell_filled(i)
		if filled:
			var rim: Color = COLOR_RIM_FILLED
			if land > 0.0:
				# 落位瞬间把描边推向近白，再随光晕一起回落
				rim = COLOR_RIM_FILLED.lerp(Color(1, 1, 1, 1), land * 0.75)
			_style_filled.border_color = rim
			_style_filled.bg_color = COLOR_CELL_BG_FILLED
			draw_style_box(_style_filled, rect)
		else:
			var rim: Color = COLOR_RIM_EMPTY
			rim.a = _empty_rim_alpha(i)
			_style_empty.border_color = rim
			_style_empty.bg_color = COLOR_CELL_BG_EMPTY
			draw_style_box(_style_empty, rect)
		if land > 0.0:
			var glow: Color = COLOR_GLOW
			glow.a = land * 0.85
			var grow: float = (1.0 - land) * CELL_SIZE.x * 0.45
			draw_arc(center, CELL_SIZE.x * 0.5 + grow, 0.0, TAU, 30, glow, 2.5, true)
