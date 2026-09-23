## 骨骼版腓腓（世界空间角色）
##
## 承担腓腓的全部对外 API（play_entry_fly_in / settle_to_shoulder /
## show_hint / play_happy / go_idle / talk_speaking_start / talk_speaking_end / feifei_sprite），
## 驱动 Skeleton2D + AnimationPlayer，并把对话气泡作为 top_level 子节点渲染在骨骼之上（z_index 10 > 骨骼最高 2）。
##
## 气泡样式与布局逻辑沿用旧 `FeifeiShoulder.gd` 的取值。
## ⚠️ `FeifeiShoulder.gd` / `feifei_frames.tres` / `FeifeiCompanion.tscn` 已于 2026-09-15 退役删除，
## 本类是腓腓的唯一实现；全部 6 个场景（BeginningFP / MirageInnIntroduction / MirageInnHub /
## ChangAnMarket / ChangAnMarketLesson02 / WordSpiritLibraryArchiveHall）都直接实例化本组件。
class_name FeifeiBody
extends CharacterBody2D

# ——— 飞入动画参数（世界空间） ———
const ENTRY_OFFSET: Vector2 = Vector2(-400.0, -300.0)
const ENTRY_SCALE_FACTOR: float = 0.5
const ENTRY_DURATION: float = 2.0
const HAPPY_JUMP_PX: float = 15.0
const HAPPY_SCALE_POP: float = 1.3
const BREATHE_AMPLITUDE: float = 3.0
const BREATHE_PERIOD: float = 1.5

# ——— 状态常量（与 CoachOverlay 保持一致） ———
const STATE_IDLE: String = "idle"
const STATE_HINT: String = "hint"
const STATE_HAPPY: String = "happy"
const STATE_TALK: String = "talk"

# ——— 气泡样式（沿用旧 FeifeiShoulder 取值） ———
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
const BUBBLE_PANEL_Z_INDEX: int = 10
const BUBBLE_TAIL_Z_INDEX: int = 9
const BUBBLE_FONT_SIZE: int = 22
const BUBBLE_TAIL_Y_INSET: float = 2.0

# ——— 节点引用 ———
@onready var animation_player: AnimationPlayer = $AnimationPlayer
## P1 并发修正：口型独立播放器。Godot 4.6 的 AnimationPlayer 是单播放状态，
## play() 会顶掉正在播的动画——口型 talk_mouth 若与身体 talk 共用一个播放器，
## 说话时身体会冻结。口型单独一个播放器，才能与身体动画、眨眼（Tween）真并行。
@onready var face_animation_player: AnimationPlayer = $FaceAnimationPlayer
@onready var bubble_panel: Panel = $BubblePanel
@onready var bubble_label: RichTextLabel = $BubblePanel/BubbleLabel
@onready var bubble_tail: Polygon2D = $BubbleTail
@onready var bubble_anchor: Marker2D = $BubbleAnchor
## P1：嘴部部件（talk_mouth 动画驱动其 polygon 顶点）
@onready var mouth_polygon: Polygon2D = $polygons/mouth

# 控制器会 tween feifei_sprite.position/scale；骨骼整体即根节点自身。
var feifei_sprite: Node2D = self

# ——— 内部状态 ———
var _current_state: String = STATE_IDLE
var _mouth_base_polygon: PackedVector2Array
var _bubble_ttl: Timer
var _breathe_tween: Tween
var _rest_position: Vector2
var _rest_scale: Vector2

# ——— 信号 ———
signal hint_shown()
signal state_changed(new_state: String)

# ——— 生命周期 ———

func _ready() -> void:
	_rest_position = position
	_rest_scale = scale

	# 气泡脱离父变换：实例 scale 通常 0.1，否则气泡会被缩成不可读尺寸。
	bubble_panel.top_level = true
	bubble_tail.top_level = true
	bubble_panel.z_index = BUBBLE_PANEL_Z_INDEX
	bubble_tail.z_index = BUBBLE_TAIL_Z_INDEX

	_bubble_ttl = Timer.new()
	_bubble_ttl.one_shot = true
	_bubble_ttl.timeout.connect(_on_bubble_ttl)
	add_child(_bubble_ttl)

	_configure_bubble_style()
	_hide_bubble()

	# P1：记录基础嘴型（go_idle 停口型循环后恢复用）
	if mouth_polygon:
		_mouth_base_polygon = mouth_polygon.polygon.duplicate()

func _process(_delta: float) -> void:
	if bubble_panel and bubble_panel.visible:
		_update_bubble_position()

# ——— 口型动画（P1：talk_mouth 循环 mouth:polygon 顶点，由面部播放器驱动） ———

func _start_talk_mouth() -> void:
	# 用独立的面部播放器播口型循环，不与身体 AnimationPlayer 抢播放状态，
	# 因此 body talk / 眨眼 都能与口型同时进行。
	if face_animation_player and face_animation_player.has_animation("talk_mouth"):
		face_animation_player.play("talk_mouth")

func _stop_talk_mouth() -> void:
	# 只停面部播放器（它只含 talk_mouth 循环）。4.6 的 stop() 无按名参数，
	# 但面部播放器里只有一个动画，整体停即可，不会误伤身体 AnimationPlayer。
	if face_animation_player:
		face_animation_player.stop()
	# 循环中途停止时最后一帧不是基础形状，恢复基础嘴型。
	# 眼睛由 BlinkController 的 Tween 自管理（每次眨眼结束都会回到 _base_polygon），
	# 这里不碰眼睛，避免把进行中的眨眼 tween 顶掉。
	if mouth_polygon and not _mouth_base_polygon.is_empty():
		mouth_polygon.polygon = _mouth_base_polygon

# ——— 飞入动画 ———

func play_entry_fly_in() -> void:
	visible = true
	_stop_breathe()

	var entry_pos: Vector2 = _rest_position + ENTRY_OFFSET
	var entry_scale: Vector2 = _rest_scale * ENTRY_SCALE_FACTOR
	position = entry_pos
	scale = entry_scale
	modulate.a = 0.0

	if animation_player and animation_player.has_animation("fly"):
		animation_player.play("fly")

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", _rest_position, ENTRY_DURATION * 0.7) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "scale", _rest_scale, ENTRY_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate:a", 1.0, ENTRY_DURATION * 0.4) \
		.set_ease(Tween.EASE_IN)
	await tween.finished
	# 飞入结束后进入 idle：播 idle 骨骼动画（含身体浮动），停掉呼吸 tween 避免与骨骼浮动叠加。
	go_idle()

## 骨骼无肩膀锚点概念；实现一个落地小节拍以保留 await 语义。
func settle_to_shoulder() -> void:
	var pop_scale: Vector2 = _rest_scale * 1.05
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", pop_scale, 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", _rest_scale, 0.25) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

# ——— 公开 API ———

## 显示提示气泡并切换状态。
## ttl <= 0 表示不自动消失，需要调用方手动隐藏（如 go_idle）。
func show_hint(text: String, state: String = STATE_HINT, ttl: float = 3.0) -> void:
	_current_state = state
	_play_state_anim(state)
	# 口型与状态同步：只有 TALK（TTS 播报）时嘴在动，其余状态停口型并恢复基础形。
	if state == STATE_TALK:
		_start_talk_mouth()
	else:
		_stop_talk_mouth()
	_show_bubble(text)
	if ttl > 0.0:
		_bubble_ttl.start(ttl)
	else:
		_bubble_ttl.stop()
	state_changed.emit(state)
	hint_shown.emit()

## 播放对话状态（TTS 播报时）：身体保持 idle + 嘴部 talk_mouth 循环 + 随机眨眼（BlinkController 自动）。
## 可与气泡显示配合：先 play_talk()，气泡结束后 go_idle()。
func play_talk() -> void:
	_current_state = STATE_TALK
	_stop_breathe()
	_play_state_anim(STATE_TALK)
	# P1：说话时叠加循环口型动画（talk_mouth 独占 mouth:polygon，与身体骨骼无属性冲突）
	_start_talk_mouth()
	state_changed.emit(STATE_TALK)

## TTS 播报窗口开始（飞飞音 spirit 的台词行调用）：身体切 idle + 嘴部 talk_mouth 循环。
## 随机眨眼由 BlinkController 自动进行，无需此处处理。与 talk_speaking_end() 配对。
func talk_speaking_start() -> void:
	_current_state = STATE_TALK
	_stop_breathe()
	_play_state_anim(STATE_TALK)
	_start_talk_mouth()
	state_changed.emit(STATE_TALK)

## TTS 播报窗口结束：停口型并恢复基础嘴型，身体保持 idle（已在播 idle 则无动作）。
func talk_speaking_end() -> void:
	_current_state = STATE_IDLE
	_stop_talk_mouth()
	_play_state_anim(STATE_IDLE)
	state_changed.emit(STATE_IDLE)

## 播放 happy 庆祝动画（无对应骨骼动画，用 tween 模拟）。
func play_happy() -> void:
	_current_state = STATE_HAPPY
	_stop_breathe()
	# 庆祝时闭嘴（状态机完整性：非 TALK 状态口型必须停）
	_stop_talk_mouth()
	var base_y: float = _rest_position.y
	var pop_scale: Vector2 = _rest_scale * HAPPY_SCALE_POP
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:y", base_y - HAPPY_JUMP_PX, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "scale", pop_scale, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", _rest_scale, 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween.parallel().tween_property(self, "position:y", base_y, 0.4) \
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		# 庆祝动画结束只切回 idle，不清气泡：调用方通常紧接着 show_hint 新对话行，
		# 若这里 go_idle() 会把它刚显示的气泡藏掉（识别成功后气泡闪烁消失的根因）。
		go_idle(false)
	)
	state_changed.emit(STATE_HAPPY)

## 切回 idle 状态。hide_bubble=false 用于庆祝动画结束等场景，保留对话气泡。
func go_idle(hide_bubble: bool = true) -> void:
	_current_state = STATE_IDLE
	if hide_bubble:
		_hide_bubble()
	# P1：停口型动画并恢复基础嘴型（循环中途停止时最后一帧不是基础形状）
	_stop_talk_mouth()
	_play_state_anim(STATE_IDLE)
	state_changed.emit(STATE_IDLE)

func get_current_state() -> String:
	return _current_state

# ——— 呼吸动画 ———

func _start_breathe() -> void:
	_stop_breathe()
	var base_y: float = _rest_position.y
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.tween_property(self, "position:y", base_y - BREATHE_AMPLITUDE, BREATHE_PERIOD) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_property(self, "position:y", base_y + BREATHE_AMPLITUDE, BREATHE_PERIOD) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_breathe() -> void:
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()
		_breathe_tween = null

# ——— 状态动画 ———

func _play_state_anim(state: String) -> void:
	match state:
		STATE_IDLE:
			# idle 骨骼动画自带 body:position:y 上下浮动，停掉根节点呼吸 tween 避免叠加。
			_stop_breathe()
			# 已在播 idle 则不重播，避免循环相位跳变（对话行之间会频繁 go_idle/talk_speaking_end）。
			if animation_player and animation_player.current_animation != "idle" \
					and animation_player.has_animation("idle"):
				animation_player.play("idle")
		STATE_HINT:
			# 保持翅膀扇动作为"在听"的视觉，无独立 hint 动画。
			if animation_player and not animation_player.is_playing():
				animation_player.play("fly")
		STATE_HAPPY:
			pass # 由 play_happy() 驱动 tween。
		STATE_TALK:
			# TTS 播报时身体保持 idle（不播 talk 身体动画），口型由 talk_mouth（FaceAnimationPlayer）
			# 驱动、眨眼由 BlinkController（Tween）驱动，三路并行互不干扰。
			# 已在播 idle 则不重播，避免循环从头开始的相位跳变。
			if animation_player and animation_player.current_animation != "idle" \
					and animation_player.has_animation("idle"):
				animation_player.play("idle")

# ——— 气泡控制（沿用 FeifeiShoulder 布局逻辑，世界空间定位） ———

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
	bubble_label.add_theme_font_size_override("normal_font_size", BUBBLE_FONT_SIZE)

	var style := StyleBoxFlat.new()
	style.bg_color = BUBBLE_BG_COLOR
	style.border_color = BUBBLE_BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = BUBBLE_PADDING.x
	style.content_margin_top = BUBBLE_PADDING.y
	style.content_margin_right = BUBBLE_PADDING.x + BUBBLE_RIGHT_EXTRA_PADDING
	style.content_margin_bottom = BUBBLE_PADDING.y
	bubble_panel.add_theme_stylebox_override("panel", style)

	bubble_tail.color = BUBBLE_BG_COLOR
	bubble_tail.antialiased = true

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
	if not bubble_panel or not bubble_anchor:
		return
	var head_world: Vector2 = bubble_anchor.global_position
	var bubble_size := bubble_panel.size
	# 气泡放在头部正上方居中。
	var target_position := head_world - Vector2(
		bubble_size.x * 0.5,
		bubble_size.y + BUBBLE_GAP_FROM_FEIFEI.y
	)
	bubble_panel.position = target_position
	_update_bubble_tail(bubble_size)

func _update_bubble_tail(bubble_size: Vector2) -> void:
	if not bubble_tail:
		return
	# 气泡水平居中于头部上方（见 _update_bubble_position），
	# 尖头须对齐头部中点、垂直指向角色。
	var tip_x := bubble_panel.position.x + bubble_size.x * 0.5
	var base_y := bubble_panel.position.y + bubble_size.y - BUBBLE_TAIL_Y_INSET
	var half_width := BUBBLE_TAIL_SIZE.x * 0.5
	bubble_tail.polygon = PackedVector2Array([
		Vector2(tip_x - half_width, base_y),
		Vector2(tip_x + half_width, base_y),
		Vector2(tip_x, base_y + BUBBLE_TAIL_SIZE.y),
	])

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
