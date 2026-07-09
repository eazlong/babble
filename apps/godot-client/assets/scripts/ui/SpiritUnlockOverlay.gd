class_name SpiritUnlockOverlay
extends Control
## Spirit Unlock Overlay (LinguaQuest Adaptation)
## 显示词灵解锁成就动画和信息卡片
## UIFramework Layer 30 (Overlay)

signal dismissed

# Visual Design Constants
const WARM_PAPER_SEMI := Color(0.949, 0.902, 0.788, 0.7)
const JADE_GREEN := Color(0.227, 0.490, 0.373, 1.0)
const JADE_GLOW := Color(0.227, 0.490, 0.373, 0.4)
const WARM_INK_TEXT := Color(0.18, 0.14, 0.12, 1.0)
const WARM_PAPER_BG := Color(0.949, 0.902, 0.788, 1.0)
const CORNER_RADIUS := 16.0
const DISPLAY_DURATION := 3.0
const FADE_DURATION := 0.5
const CARD_POP_IN_DURATION := 0.4

# UI Components
var _background_panel: Panel
var _glow_animation: Control
var _spirit_card: Panel
var _card_container: VBoxContainer
var _spirit_image: TextureRect
var _spirit_name_label: Label
var _spirit_description_label: Label
var _rarity_label: Label

# Animation
var _display_timer: Timer
var _glow_tween: Tween
var _fade_tween: Tween
var _card_tween: Tween

# Spirit Data
var _spirit_id: String


func _ready() -> void:
	# Activate Overlay layer (dim下层UI)
	var ui_framework = get_node("/root/UIFramework")
	ui_framework.activate_overlay()

	_setup_background()
	_setup_glow_animation()
	_setup_spirit_card()
	_setup_animation()


func _setup_background() -> void:
	_background_panel = Panel.new()
	_background_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_panel.modulate = WARM_PAPER_SEMI

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = WARM_PAPER_SEMI
	_background_panel.add_theme_stylebox_override("panel", bg_style)

	add_child(_background_panel)


func _setup_glow_animation() -> void:
	_glow_animation = Control.new()
	_glow_animation.set_anchors_preset(Control.PRESET_CENTER)
	_glow_animation.custom_minimum_size = Vector2(200, 200)

	var glow_panel := Panel.new()
	glow_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow_panel.modulate = JADE_GLOW

	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = JADE_GLOW
	glow_style.corner_radius_top_left = 100.0
	glow_style.corner_radius_top_right = 100.0
	glow_style.corner_radius_bottom_left = 100.0
	glow_style.corner_radius_bottom_right = 100.0
	glow_panel.add_theme_stylebox_override("panel", glow_style)

	_glow_animation.add_child(glow_panel)
	_background_panel.add_child(_glow_animation)


func _setup_spirit_card() -> void:
	_spirit_card = Panel.new()
	_spirit_card.set_anchors_preset(Control.PRESET_CENTER)

	# Fixed card size for MVP
	_spirit_card.custom_minimum_size = Vector2(400.0, 300.0)
	_spirit_card.size = Vector2(400.0, 300.0)
	_spirit_card.position.y = 120

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = WARM_PAPER_BG
	card_style.corner_radius_top_left = CORNER_RADIUS
	card_style.corner_radius_top_right = CORNER_RADIUS
	card_style.corner_radius_bottom_left = CORNER_RADIUS
	card_style.corner_radius_bottom_right = CORNER_RADIUS
	card_style.border_color = JADE_GREEN
	card_style.border_width_top = 3
	card_style.border_width_bottom = 3
	card_style.border_width_left = 3
	card_style.border_width_right = 3

	_spirit_card.add_theme_stylebox_override("panel", card_style)
	_background_panel.add_child(_spirit_card)

	# Card content container
	_card_container = VBoxContainer.new()
	_card_container.set_anchors_preset(Control.PRESET_CENTER)
	_card_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_container.add_theme_constant_override("separation", 16)

	_spirit_card.add_child(_card_container)

	# Spirit image placeholder
	_spirit_image = TextureRect.new()
	_spirit_image.custom_minimum_size = Vector2(150, 150)
	_spirit_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spirit_image.texture = null
	_card_container.add_child(_spirit_image)

	# Spirit name
	_spirit_name_label = Label.new()
	_spirit_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spirit_name_label.add_theme_font_size_override("font_size", 22)
	_spirit_name_label.add_theme_color_override("font_color", WARM_INK_TEXT)
	_card_container.add_child(_spirit_name_label)

	# Spirit description
	_spirit_description_label = Label.new()
	_spirit_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spirit_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spirit_description_label.custom_minimum_size = Vector2(350, 80)
	_spirit_description_label.add_theme_font_size_override("font_size", 18)
	_spirit_description_label.add_theme_color_override("font_color", WARM_INK_TEXT)
	_card_container.add_child(_spirit_description_label)

	# Rarity badge
	_rarity_label = Label.new()
	_rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rarity_label.add_theme_font_size_override("font_size", 18)
	_rarity_label.add_theme_color_override("font_color", JADE_GREEN)
	_card_container.add_child(_rarity_label)


func _setup_animation() -> void:
	_display_timer = Timer.new()
	_display_timer.wait_time = DISPLAY_DURATION
	_display_timer.one_shot = true
	_display_timer.timeout.connect(_start_fade_out)
	add_child(_display_timer)

	_background_panel.modulate.a = 0.0


func display_spirit_unlock(spirit_id: String) -> void:
	_spirit_id = spirit_id

	# Load spirit data from SpiritDatabase
	var spirit_data = SpiritDatabase.get_spirit(spirit_id)
	if spirit_data.is_empty():
		push_error("SpiritUnlockOverlay: Failed to load spirit data for " + spirit_id)
		return

	# Multi-language support
	var lang = GameManager.current_lang
	var name_dict = spirit_data.get("name", {})
	_spirit_name_label.text = name_dict.get(lang, name_dict.get("en", "Unknown"))
	_spirit_description_label.text = spirit_data.get("description", "")

	# Rarity label with color
	var rarity = spirit_data.get("rarity", "common")
	_rarity_label.text = _get_rarity_label(rarity)
	_rarity_label.add_theme_color_override("font_color", _get_rarity_color(rarity))

	# Start animations
	_start_glow_animation()
	_display_timer.start()

	# Fade-in background
	_fade_tween = create_tween()
	_fade_tween.tween_property(_background_panel, "modulate:a", 1.0, FADE_DURATION)

	# Pop-in spirit card
	_spirit_card.scale = Vector2(0.8, 0.8)
	_card_tween = create_tween()
	_card_tween.tween_property(_spirit_card, "scale", Vector2(1.0, 1.0), CARD_POP_IN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _get_rarity_label(rarity: String) -> String:
	var labels = {
		"common": "普通",
		"rare": "稀有",
		"legendary": "传说"
	}
	return labels.get(rarity, "普通")


func _get_rarity_color(rarity: String) -> Color:
	var colors = {
		"common": JADE_GREEN,
		"rare": Color(0.2, 0.4, 0.8, 1.0),  # Blue
		"legendary": Color(0.9, 0.7, 0.2, 1.0)  # Gold
	}
	return colors.get(rarity, JADE_GREEN)


func _start_glow_animation() -> void:
	_glow_tween = create_tween()
	_glow_tween.set_loops(3)
	_glow_tween.tween_property(_glow_animation, "scale", Vector2(1.2, 1.2), 0.5)
	_glow_tween.tween_property(_glow_animation, "scale", Vector2(1.0, 1.0), 0.5)


func _start_fade_out() -> void:
	_fade_tween = create_tween()
	_fade_tween.tween_property(_background_panel, "modulate:a", 0.0, FADE_DURATION)
	_fade_tween.tween_callback(_on_dismissed)


func _on_dismissed() -> void:
	var ui_framework = get_node("/root/UIFramework")
	ui_framework.deactivate_overlay()
	emit_signal("dismissed")
	queue_free()
