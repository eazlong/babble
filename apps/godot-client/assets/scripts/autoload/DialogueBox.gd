extends CanvasLayer

var dialogue_panel: PanelContainer
var npc_name_label: Label
var message_label: Label
var voice_indicator: Control
var is_showing: bool = false
var chinese_font: FontFile

signal message_displayed()
signal voice_started()
signal voice_stopped()

func _ready() -> void:
	_load_font()
	_create_ui()

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
	dialogue_panel.visible = true
	is_showing = true

	npc_name_label.text = npc_id
	message_label.text = message

	voice_indicator.visible = false

	message_displayed.emit()

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
