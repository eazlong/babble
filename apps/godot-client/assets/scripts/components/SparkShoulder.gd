## Spark肩膀精灵（第一人称模式）
##
## 固定在屏幕右下角(0.9, 0.75)，承担CoachOverlay在第一人称下的简化呈现。
## 复用CoachOverlay的动画资源，但位置和尺寸固定。
##
## MVP阶段仅实现 idle/hint/happy 三个核心状态。
class_name SparkShoulder
extends Control

# ——— 位置常量 ———
const SHOULD_ANCHOR: Vector2 = Vector2(0.9, 0.63)
const SPRITE_SIZE: Vector2 = Vector2(120, 160)

# ——— 飞入动画参数 ———
const ENTRY_OFFSET: Vector2 = Vector2(-300.0, -200.0)
const ENTRY_SCALE: Vector2 = Vector2(0.4, 0.4)
const ENTRY_DURATION: float = 2.4

# ——— 状态常量（与CoachOverlay保持一致） ———
const STATE_IDLE: String = "idle"
const STATE_HINT: String = "hint"
const STATE_HAPPY: String = "happy"

# ——— 节点引用 ———
@onready var spark_sprite: AnimatedSprite2D = $SparkSprite
@onready var bubble_panel: Panel = $BubblePanel
@onready var bubble_label: RichTextLabel = $BubblePanel/BubbleLabel

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

	_hide_bubble()
	# 呼吸动画延迟到飞入动画结束后启动

func _process(_delta: float) -> void:
	if bubble_panel and spark_sprite and bubble_panel.visible:
		bubble_panel.position = spark_sprite.position + Vector2(-200, -100)

# ——— 飞入动画 ———

## Spark 从远处小点飞入屏幕中央，放大。飞入完成后 await 结束，等待外部调用 settle_to_shoulder()。
func play_entry_fly_in() -> void:
	if not spark_sprite:
		return
	_is_entry_done = false
	_stop_breathe()

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var center_pos: Vector2 = vp_size * 0.5
	var entry_pos: Vector2 = center_pos + ENTRY_OFFSET

	# 初始状态：远处小点
	spark_sprite.position = entry_pos
	spark_sprite.scale = ENTRY_SCALE
	spark_sprite.modulate.a = 0.0
	visible = true

	if spark_sprite.sprite_frames and spark_sprite.sprite_frames.has_animation("default"):
		spark_sprite.play("default")

	# 从远处飞向屏幕中央，同步放大
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark_sprite, "position", center_pos, ENTRY_DURATION * 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(spark_sprite, "scale", Vector2.ONE, ENTRY_DURATION * 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(spark_sprite, "modulate:a", 1.0, ENTRY_DURATION * 0.3) \
		.set_ease(Tween.EASE_IN)
	await tween.finished

## 从屏幕中央滑落到肩膀位置，飞入动画的最终阶段。
func settle_to_shoulder() -> void:
	if not spark_sprite:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var shoulder_pos: Vector2 = Vector2(
		vp_size.x * SHOULD_ANCHOR.x,
		vp_size.y * SHOULD_ANCHOR.y
	)
	var tween: Tween = create_tween()
	tween.tween_property(spark_sprite, "position", shoulder_pos, ENTRY_DURATION * 0.4) \
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
	if spark_sprite:
		spark_sprite.position = Vector2(target_x, target_y)

# ——— 呼吸动画 ———

func _start_breathe() -> void:
	_stop_breathe()
	if not spark_sprite:
		return
	var base_y: float = spark_sprite.position.y
	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.tween_property(spark_sprite, "position:y", base_y - 3.0, 1.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_property(spark_sprite, "position:y", base_y + 3.0, 1.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_breathe() -> void:
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()
		_breathe_tween = null

# ——— 状态动画 ———

func _play_state_anim(state: String) -> void:
	if not spark_sprite:
		return
	_stop_breathe()

	match state:
		STATE_IDLE:
			spark_sprite.visible = true
			spark_sprite.modulate = Color.WHITE
			_play_sprite_anim(STATE_IDLE)
			_start_breathe()

		STATE_HINT:
			spark_sprite.visible = true
			spark_sprite.modulate = Color.WHITE
			_play_sprite_anim(STATE_HINT)
			# 缓慢浮动
			var base_y: float = spark_sprite.position.y
			_breathe_tween = create_tween()
			_breathe_tween.set_loops()
			_breathe_tween.tween_property(spark_sprite, "position:y", base_y - 3.0, 2.5) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			_breathe_tween.tween_property(spark_sprite, "position:y", base_y + 3.0, 2.5) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

		STATE_HAPPY:
			spark_sprite.visible = true
			# 跳跃 + 放大
			var base_y: float = spark_sprite.position.y
			var tween: Tween = create_tween()
			tween.tween_property(spark_sprite, "position:y", base_y - 15.0, 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.parallel().tween_property(spark_sprite, "scale", Vector2(1.15, 1.15), 0.3) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tween.tween_property(spark_sprite, "scale", Vector2(1.0, 1.0), 0.4) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)
			tween.parallel().tween_property(spark_sprite, "position:y", base_y, 0.4) \
				.set_ease(Tween.EASE_IN_OUT)
			tween.tween_callback(func():
				go_idle()
			)
			_play_sprite_anim(STATE_HAPPY)

func _play_sprite_anim(anim_name: String) -> void:
	if spark_sprite.sprite_frames and spark_sprite.sprite_frames.has_animation(anim_name):
		spark_sprite.play(anim_name)
	elif spark_sprite.sprite_frames and spark_sprite.sprite_frames.has_animation(STATE_IDLE):
		spark_sprite.play(STATE_IDLE)

# ——— 气泡控制 ———

func _show_bubble(text: String) -> void:
	if not bubble_panel or not bubble_label:
		return
	bubble_label.text = text
	bubble_panel.visible = true
	bubble_panel.modulate.a = 0.0
	bubble_panel.scale = Vector2(0.6, 0.6)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(bubble_panel, "modulate:a", 1.0, 0.25)
	tween.tween_property(bubble_panel, "scale", Vector2(1.0, 1.0), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_bubble() -> void:
	if not bubble_panel:
		return
	bubble_panel.visible = false
	bubble_panel.modulate.a = 0.0

func _on_bubble_ttl() -> void:
	_hide_bubble()
	go_idle()
