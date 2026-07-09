## 词灵预览组件
##
## 进入场景时显示 Spark 提示："这里可能住着……"
## 展示当前场景可能遇到的词灵（未解锁的）。
## 3 秒后自动消失。
##
extends Control

@export var preview_duration: float = 3.0

var _bg_panel: Panel
var _spark_label: Label
var _spirit_icon: Label
var _tween: Tween

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	"""构建预览 UI"""
	# 背景面板
	_bg_panel = Panel.new()
	_bg_panel.set_anchors_preset(Control.PRESET_CENTER)
	_bg_panel.offset_left = -200
	_bg_panel.offset_top = -60
	_bg_panel.offset_right = 200
	_bg_panel.offset_bottom = 60
	add_child(_bg_panel)

	# Spark 标签
	_spark_label = Label.new()
	_spark_label.set_anchors_preset(Control.PRESET_CENTER)
	_spark_label.offset_left = -180
	_spark_label.offset_top = -40
	_spark_label.offset_right = 180
	_spark_label.offset_bottom = 40
	_spark_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spark_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_spark_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_spark_label.add_theme_font_size_override("font_size", 16)
	add_child(_spark_label)

	# 词灵图标
	_spirit_icon = Label.new()
	_spirit_icon.anchor_left = 0.5
	_spirit_icon.anchor_right = 0.5
	_spirit_icon.anchor_top = 1.0
	_spirit_icon.anchor_bottom = 1.0
	_spirit_icon.offset_left = -20
	_spirit_icon.offset_top = -40
	_spirit_icon.offset_right = 20
	_spirit_icon.offset_bottom = -10
	_spirit_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spirit_icon.add_theme_font_size_override("font_size", 28)
	add_child(_spirit_icon)

func show_preview(spirit_name: String, spirit_hint_zh: String, spirit_hint_en: String, icon: String = "✨") -> void:
	"""
	显示词灵预览。
	spirit_name: 词灵名称（如 "Sunshine"）
	spirit_hint_zh: 中文提示
	spirit_hint_en: 英文提示
	icon: 图标 emoji
	"""
	var hint = spirit_hint_zh if GameManager.current_lang == "zh" else spirit_hint_en

	_spark_label.text = "✨ Spark:\n" + hint
	_spirit_icon.text = icon

	visible = true
	modulate.a = 0.0

	# 飞入动画
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.tween_interval(preview_duration)
	_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	_tween.tween_callback(func(): visible = false)

func hide_preview() -> void:
	if _tween:
		_tween.kill()
	visible = false
