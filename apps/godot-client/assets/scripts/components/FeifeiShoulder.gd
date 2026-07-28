## Feifei肩膀精灵（第一人称模式）
##
## 固定在屏幕右下角(0.9, 0.75)，承担CoachOverlay在第一人称下的简化呈现。
## 复用CoachOverlay的动画资源，但位置和尺寸固定。
##
## MVP阶段仅实现 idle/hint/happy 三个核心状态。
class_name FeifeiShoulder
extends Control

# ——— 位置常量 ———
const SHOULD_ANCHOR: Vector2 = Vector2(0.9, 0.63)
const SPRITE_SIZE: Vector2 = Vector2(120, 160)

# ——— 飞入动画参数 ———
const ENTRY_OFFSET: Vector2 = Vector2(-200.0, -200.0)
const ENTRY_TARGET_OFFSET: Vector2 = Vector2(0.0, 100.0)
const ENTRY_SCALE: Vector2 = Vector2(0.4, 0.4)
const ENTRY_DURATION: float = 4.8

# ——— 状态常量（与CoachOverlay保持一致） ———
const STATE_IDLE: String = "idle"
const STATE_HINT: String = "hint"
const STATE_HAPPY: String = "happy"
const BUBBLE_MIN_SIZE: Vector2 = Vector2(260.0, 112.0)
const BUBBLE_MAX_WIDTH: float = 620.0
const BUBBLE_PADDING: Vector2 = Vector2(32.0, 24.0)
const BUBBLE_RIGHT_EXTRA_PADDING: float = 24.0
const BUBBLE_LINE_HEIGHT: float = 34.0
const BUBBLE_AVERAGE_CHAR_WIDTH: float = 20.0
const BUBBLE_GAP_FROM_FEIFEI: Vector2 = Vector2(26.0, 32.0)
const BUBBLE_BG_COLOR: Color = Color("#656565")
const BUBBLE_BORDER_COLOR: Color = Color(0.95, 0.77, 0.28, 0.9)
const BUBBLE_TEXT_COLOR: Color = Color(1.0, 0.96, 0.82, 1.0)
const BUBBLE_TAIL_SIZE: Vector2 = Vector2(42.0, 28.0)
const BUBBLE_TAIL_RIGHT_OFFSET: float = 42.0

# ——— 节点引用 ———
@onready var feifei_sprite: AnimatedSprite2D = $FeifeiSprite
@onready var bubble_panel: Control = $BubblePanel
@onready var bubble_label: RichTextLabel = $BubblePanel/BubbleLabel
@onready var bubble_tail: Polygon2D = get_node_or_null("BubbleTail") as Polygon2D

# ——— 内部状态 ———
var _current_state: String = STATE_IDLE
var _breathe_tween: Tween
var _bubble_ttl: Timer
var _is_entry_done: bool = false

# ——— 信号 ———
signal hint_shown()
signal state_changed(new_state: String)

# ——— 生命周期 ———

func _ready() -> void:
	# 全屏锚定，自身不响应输入
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	get_viewport().size_changed.connect(_update_position)

	# 气泡TTL
	_bubble_ttl = Timer.new()
	_bubble_ttl.one_shot = true
	_bubble_ttl.timeout.connect(_on_bubble_ttl)
	add_child(_bubble_ttl)

	_configure_bubble_style()
	_hide_bubble()
	# 呼吸动画延迟到飞入动画结束后启动

func _process(_delta: float) -> void:
	if bubble_panel and feifei_sprite and bubble_panel.visible:
		_update_bubble_position()

# ——— 飞入动画 ———

## Feifei 从远处小点飞入屏幕中央，放大。飞入完成后 await 结束，等待外部调用 settle_to_shoulder()。
func play_entry_fly_in() -> void:
	if not feifei_sprite:
		return
	_is_entry_done = false
	_stop_breathe()

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var center_pos: Vector2 = vp_size * 0.5
	var entry_pos: Vector2 = center_pos + ENTRY_OFFSET
	var entry_target_pos: Vector2 = center_pos + ENTRY_TARGET_OFFSET

	# 初始状态：远处小点
	feifei_sprite.position = entry_pos
	feifei_sprite.scale = ENTRY_SCALE
	feifei_sprite.modulate.a = 0.0
	visible = true

	if feifei_sprite.sprite_frames and feifei_sprite.sprite_frames.has_animation("fly"):
		feifei_sprite.play("fly")

	# 从远处飞向屏幕中央，同步放大
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(feifei_sprite, "position", entry_target_pos, ENTRY_DURATION * 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(feifei_sprite, "scale", Vector2.ONE, ENTRY_DURATION * 1.0) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(feifei_sprite, "modulate:a", 1.0, ENTRY_DURATION * 0.3) \
		.set_ease(Tween.EASE_IN)
	await tween.finished

## 从屏幕中央滑落到肩膀位置，飞入动画的最终阶段。
func settle_to_shoulder() -> void:
	if not feifei_sprite:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var shoulder_pos: Vector2 = Vector2(
		vp_size.x * SHOULD_ANCHOR.x,
		vp_size.y * SHOULD_ANCHOR.y
	)
	var tween: Tween = create_tween()
	tween.tween_property(feifei_sprite, "position", shoulder_pos, ENTRY_DURATION * 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	_is_entry_done = true
	_update_position()
	_start_breathe()

# ——— 公开API ———

## 显示提示气泡并切换状态
## ttl <= 0 表示不自动消失，需要调用方手动隐藏（如 go_idle）
func show_hint(text: String, state: String = STATE_HINT, ttl: float = 3.0) -> void:
	_current_state = state
	_play_state_anim(state)
	_show_bubble(text)
	if ttl > 0.0:
		_bubble_ttl.start(ttl)
	else:
		_bubble_ttl.stop()
	state_changed.emit(state)
	hint_shown.emit()

## 播放happy庆祝动画
func play_happy() -> void:
	_current_state = STATE_HAPPY
	_play_state_anim(STATE_HAPPY)
	state_changed.emit(STATE_HAPPY)

## 切回idle状态
func go_idle() -> void:
	_current_state = STATE_IDLE
	_hide_bubble()
	_start_breathe()
	state_changed.emit(STATE_IDLE)

func get_current_state() -> String:
	return _current_state

# ——— 位置控制 ———

func _update_position() -> void:
	if not _is_entry_done:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var target_x: float = vp_size.x * SHOULD_ANCHOR.x
	var target_y: float = vp_size.y * SHOULD_ANCHOR.y
	if feifei_sprite:
		feifei_sprite.position = Vector2(target_x, target_y)

# ——— 呼吸动画 ———

func _start_breathe() -> void:
	_stop_breathe()
	if not feifei_sprite:
		return
	var base_y: float = feifei_sprite.position.y
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.tween_property(feifei_sprite, "position:y", base_y - 3.0, 1.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_property(feifei_sprite, "position:y", base_y + 3.0, 1.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_breathe() -> void:
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()
		_breathe_tween = null

# ——— 状态动画 ———

func _play_state_anim(state: String) -> void:
	if not feifei_sprite:
		return
	_stop_breathe()

	match state:
		STATE_IDLE:
			feifei_sprite.visible = true
			feifei_sprite.modulate = Color.WHITE
			_play_sprite_anim(STATE_IDLE)
			_start_breathe()

		STATE_HINT:
			feifei_sprite.visible = true
			feifei_sprite.modulate = Color.WHITE
			_play_sprite_anim(STATE_HINT)
			# 缓慢浮动
			var base_y: float = feifei_sprite.position.y
			_breathe_tween = create_tween()
			_breathe_tween.set_loops()
			_breathe_tween.tween_property(feifei_sprite, "position:y", base_y - 3.0, 2.5) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			_breathe_tween.tween_property(feifei_sprite, "position:y", base_y + 3.0, 2.5) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

		STATE_HAPPY:
			feifei_sprite.visible = true
			# 跳跃 + 放大
			var base_y: float = feifei_sprite.position.y
			var tween: Tween = create_tween()
			tween.tween_property(feifei_sprite, "position:y", base_y - 15.0, 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.parallel().tween_property(feifei_sprite, "scale", Vector2(1.15, 1.15), 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_property(feifei_sprite, "scale", Vector2(1.0, 1.0), 0.4) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)
			tween.parallel().tween_property(feifei_sprite, "position:y", base_y, 0.4) \
				.set_ease(Tween.EASE_IN_OUT)
			tween.tween_callback(func():
				go_idle()
			)
			_play_sprite_anim(STATE_HAPPY)

func _play_sprite_anim(anim_name: String) -> void:
	if feifei_sprite.sprite_frames and feifei_sprite.sprite_frames.has_animation(anim_name):
		feifei_sprite.play(anim_name)
	elif feifei_sprite.sprite_frames and feifei_sprite.sprite_frames.has_animation(STATE_IDLE):
		feifei_sprite.play(STATE_IDLE)

# ——— 气泡控制 ———

func _show_bubble(text: String) -> void:
	if not bubble_panel or not bubble_label:
		return
	bubble_label.text = text
	_resize_bubble_for_text(text)
	_update_bubble_position()
	bubble_panel.visible = true
	bubble_panel.modulate.a = 0.0
	bubble_panel.scale = Vector2(0.6, 0.6)
	if bubble_tail:
		bubble_tail.visible = true
		bubble_tail.modulate.a = 0.0
		bubble_tail.scale = Vector2(0.6, 0.6)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bubble_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(bubble_panel, "scale", Vector2(1.0, 1.0), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if bubble_tail:
		tween.tween_property(bubble_tail, "modulate:a", 1.0, 0.25)
		tween.tween_property(bubble_tail, "scale", Vector2(1.0, 1.0), 0.25) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_bubble() -> void:
	if not bubble_panel:
		return
	bubble_panel.visible = false
	bubble_panel.modulate.a = 0.0
	if bubble_tail:
		bubble_tail.visible = false
		bubble_tail.modulate.a = 0.0

func _configure_bubble_style() -> void:
	if not bubble_panel or not bubble_label:
		return

	bubble_label.bbcode_enabled = true
	bubble_label.scroll_active = false
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.fit_content = true
	bubble_label.clip_contents = false
	bubble_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bubble_label.add_theme_color_override("default_color", BUBBLE_TEXT_COLOR)
	bubble_label.add_theme_font_size_override("normal_font_size", 22)
	_ensure_bubble_tail()

	if bubble_panel is TextureRect:
		var texture_panel := bubble_panel as TextureRect
		texture_panel.self_modulate = BUBBLE_BG_COLOR
		texture_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_panel.stretch_mode = TextureRect.STRETCH_SCALE
	elif bubble_panel is Panel:
		var style := StyleBoxFlat.new()
		style.bg_color = BUBBLE_BG_COLOR
		style.border_color = BUBBLE_BORDER_COLOR
		style.set_border_width_all(2)
		style.set_corner_radius_all(14)
		style.content_margin_left = BUBBLE_PADDING.x
		style.content_margin_top = BUBBLE_PADDING.y
		style.content_margin_right = BUBBLE_PADDING.x + BUBBLE_RIGHT_EXTRA_PADDING
		style.content_margin_bottom = BUBBLE_PADDING.y
		(bubble_panel as Panel).add_theme_stylebox_override("panel", style)

func _resize_bubble_for_text(text: String) -> void:
	var clean_text := _strip_simple_bbcode(text)
	var char_count := maxi(clean_text.length(), 1)
	var target_width := clampf(
		char_count * BUBBLE_AVERAGE_CHAR_WIDTH + BUBBLE_PADDING.x * 2.0 + BUBBLE_RIGHT_EXTRA_PADDING,
		BUBBLE_MIN_SIZE.x,
		BUBBLE_MAX_WIDTH
	)
	var horizontal_padding := BUBBLE_PADDING.x * 2.0 + BUBBLE_RIGHT_EXTRA_PADDING
	var chars_per_line := maxi(int(floor((target_width - horizontal_padding) / BUBBLE_AVERAGE_CHAR_WIDTH)), 1)
	var line_count := maxi(int(ceil(float(char_count) / float(chars_per_line))), 1)
	var target_height := maxf(
		BUBBLE_MIN_SIZE.y,
		line_count * BUBBLE_LINE_HEIGHT + BUBBLE_PADDING.y * 2.0
	)
	var target_size := Vector2(target_width, target_height)

	bubble_panel.custom_minimum_size = target_size
	bubble_panel.size = target_size
	bubble_label.position = BUBBLE_PADDING
	bubble_label.size = target_size - Vector2(horizontal_padding, BUBBLE_PADDING.y * 2.0)
	_update_bubble_tail(target_size)

func _update_bubble_position() -> void:
	if not bubble_panel or not feifei_sprite:
		return
	var bubble_size := bubble_panel.size
	var target_position := feifei_sprite.position - Vector2(
		bubble_size.x + BUBBLE_GAP_FROM_FEIFEI.x,
		bubble_size.y + BUBBLE_GAP_FROM_FEIFEI.y
	)
	var vp_size := get_viewport().get_visible_rect().size
	target_position.x = clampf(target_position.x, 12.0, maxf(12.0, vp_size.x - bubble_size.x - 12.0))
	target_position.y = clampf(target_position.y, 12.0, maxf(12.0, vp_size.y - bubble_size.y - 12.0))
	bubble_panel.position = target_position
	_update_bubble_tail(bubble_size)

func _update_bubble_tail(bubble_size: Vector2) -> void:
	if not bubble_tail:
		return
	var base_x := bubble_panel.position.x + maxf(
		BUBBLE_PADDING.x,
		bubble_size.x - BUBBLE_TAIL_RIGHT_OFFSET - BUBBLE_TAIL_SIZE.x
	)
	var base_y := bubble_panel.position.y + bubble_size.y - 2.0
	bubble_tail.polygon = PackedVector2Array([
		Vector2(base_x, base_y),
		Vector2(base_x + BUBBLE_TAIL_SIZE.x, base_y),
		Vector2(base_x + BUBBLE_TAIL_SIZE.x + 18.0, base_y + BUBBLE_TAIL_SIZE.y),
	])

func _ensure_bubble_tail() -> void:
	if bubble_tail or not bubble_panel:
		return
	bubble_tail = Polygon2D.new()
	bubble_tail.name = "BubbleTail"
	bubble_tail.color = BUBBLE_BG_COLOR
	bubble_tail.antialiased = true
	bubble_tail.z_index = 1
	bubble_tail.visible = false
	add_child(bubble_tail)

func _strip_simple_bbcode(text: String) -> String:
	var output := ""
	var inside_tag := false
	for index in range(text.length()):
		var character := text.substr(index, 1)
		if character == "[":
			inside_tag = true
			continue
		if character == "]":
			inside_tag = false
			continue
		if not inside_tag:
			output += character
	return output

func _on_bubble_ttl() -> void:
	_hide_bubble()
	go_idle()
