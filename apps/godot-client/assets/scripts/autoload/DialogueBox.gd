extends CanvasLayer

## ============================================================
## Node引用
## ============================================================

var dialogue_panel: PanelContainer
var npc_name_label: Label
var message_label: Label
var voice_indicator: Control

## ============================================================
## 动画状态
## ============================================================

var is_showing: bool = false
var chinese_font: FontFile
var _display_tween: Tween
var _typing_timer: Timer
var _current_message: String = ""
var _typing_index: int = 0
var _typing_speed: float = 0.05  ## 每字符间隔（秒）

## ============================================================
## 信号定义
## ============================================================

signal message_displayed()
signal voice_started()
signal voice_stopped()

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
	# Set layer to 20 (DialogueCanvasLayer)
	layer = 20
	print("[DialogueBox] Set layer to 20 (DialogueCanvasLayer)")

	_load_font()
	_create_ui()
	_create_typing_timer()

func _create_typing_timer() -> void:
	# 创建逐字显示Timer
	_typing_timer = Timer.new()
	_typing_timer.one_shot = false
	_typing_timer.timeout.connect(_on_typing_tick)
	add_child(_typing_timer)

func _load_font() -> void:
	# 加载中文字体资源
	chinese_font = load("res://assets/resources/fonts/STHeiti.ttc")
	if chinese_font == null:
		push_warning("Chinese font not loaded, text may not display correctly")

func _create_ui() -> void:
	dialogue_panel = PanelContainer.new()
	dialogue_panel.name = "DialoguePanel"
	dialogue_panel.visible = false
	dialogue_panel.custom_minimum_size = Vector2(400, 150)
	dialogue_panel.position = Vector2(50, 50)

	# 设置面板背景样式 - 半透明白色背景
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(1.0, 1.0, 1.0, 0.9)  # 白色背景，90%透明度
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.border_color = Color(0.2, 0.2, 0.2, 1.0)  # 深灰色边框
	style_box.set_border_width_all(2)
	dialogue_panel.add_theme_stylebox_override("panel", style_box)

	var vbox = VBoxContainer.new()
	dialogue_panel.add_child(vbox)

	npc_name_label = Label.new()
	npc_name_label.name = "NPCName"
	npc_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if chinese_font:
		npc_name_label.add_theme_font_override("font", chinese_font)
	npc_name_label.add_theme_font_size_override("font_size", 18)
	npc_name_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))  # 深灰色文字
	npc_name_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.5))
	npc_name_label.add_theme_constant_override("outline_size", 1)
	vbox.add_child(npc_name_label)

	message_label = Label.new()
	message_label.name = "Message"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if chinese_font:
		message_label.add_theme_font_override("font", chinese_font)
	message_label.add_theme_font_size_override("font_size", 14)
	message_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))  # 深灰色文字
	vbox.add_child(message_label)

	voice_indicator = Control.new()
	voice_indicator.name = "VoiceIndicator"
	voice_indicator.visible = false
	voice_indicator.custom_minimum_size = Vector2(30, 30)
	vbox.add_child(voice_indicator)

	add_child(dialogue_panel)

func show_message(npc_id: String, message: String) -> void:
	# 弹出动画
	dialogue_panel.visible = true
	dialogue_panel.modulate.a = 0.0
	dialogue_panel.scale = Vector2(UIAnimationPresets.ScalePop.START_SCALE,
								   UIAnimationPresets.ScalePop.START_SCALE)
	is_showing = true

	npc_name_label.text = npc_id

	# 播放弹出动画
	var tween = dialogue_panel.create_tween()
	tween.set_trans(UIAnimationPresets.ScalePop.TRANS)
	tween.set_ease(UIAnimationPresets.ScalePop.EASE)

	tween.tween_property(dialogue_panel, "modulate:a", 1.0, 0.2)
	tween.tween_property(dialogue_panel, "scale",
						 Vector2(UIAnimationPresets.ScalePop.OVERSHOOT,
								 UIAnimationPresets.ScalePop.OVERSHOOT),
						 UIAnimationPresets.ScalePop.DURATION * 0.6)
	tween.tween_property(dialogue_panel, "scale",
						 Vector2(1.0, 1.0),
						 UIAnimationPresets.ScalePop.DURATION * 0.4)

	voice_indicator.visible = false

	# 启动逐字显示动画
	_start_typing_animation(message)

## ============================================================
## 逐字显示动画（打字机效果）
## ============================================================

func _start_typing_animation(message: String) -> void:
	_current_message = message
	_typing_index = 0
	message_label.text = ""

	# 根据消息长度调整速度
	var char_count = message.length()
	if char_count > 50:
		_typing_speed = 0.03  # 快速显示长文本
	else:
		_typing_speed = 0.05  # 普通速度

	_typing_timer.wait_time = _typing_speed
	_typing_timer.start()

func _on_typing_tick() -> void:
	if _typing_index >= _current_message.length():
		_typing_timer.stop()
		message_displayed.emit()
		return

	# 添加下一个字符
	_typing_index += 1
	message_label.text = _current_message.substr(0, _typing_index)

	# 可选：播放打字音效
	# AudioManager.play_sfx("typing_tick")

## ============================================================
## TTS同步（根据语音时长调整速度）
## ============================================================

func sync_with_tts(audio_duration: float) -> void:
	# 计算每字符间隔：总时长 / 字符数
	var char_count = _current_message.length()
	if char_count > 0 and audio_duration > 0:
		_typing_speed = audio_duration / char_count
		_typing_timer.wait_time = _typing_speed

func show_voice_listening() -> void:
	voice_indicator.visible = true
	voice_started.emit()

func hide_voice_listening() -> void:
	voice_indicator.visible = false
	voice_stopped.emit()

func hide_message() -> void:
	dialogue_panel.visible = false
	is_showing = false

func is_active() -> bool:
	return is_showing
