## 环境交互物体基类
##
## 所有可交互场景物体（L3）继承此类。
## 支持：点击提示、关键词触发、冷却、词灵触发检测。
##
## 使用方式：
##   1. 场景中添加 Area2D 节点
##   2. 挂载此脚本
##   3. 配置 object_id 和 interaction_keywords
##
extends Area2D

## 物体唯一标识
@export var object_id: String = ""

## 触发此交互的关键词列表
@export var interaction_keywords: Array[String] = []

## 交互成功后的 NPC 台词（用于 TTS 和气泡）
@export var response_text_zh: String = ""
@export var response_text_en: String = ""

## 冷却时间（秒）
@export var cooldown_seconds: float = 3.0

## 是否启用
@export var enabled: bool = true

## 是否已激活（部分物体需要"激活"状态，如蘑菇从暗到亮）
@export var is_activated: bool = false

## 视觉反馈类型
@export_enum("none", "pulse", "glow", "bounce", "color_shift") var visual_effect: String = "pulse"

# ——— 内部状态 ———
var _last_interaction_time: float = 0.0
var _interaction_count: int = 0
var _hint_label: Label
var _hint_tween: Tween

signal interacted(object_id: String, keyword: String)
signal activated(object_id: String)

func _ready() -> void:
	_create_hint_label()
	input_pickable = true
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func _create_hint_label() -> void:
	"""创建交互提示标签"""
	_hint_label = Label.new()
	_hint_label.visible = false
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color.WHITE)
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.text = "..."
	add_child(_hint_label)

func _on_mouse_entered() -> void:
	if not enabled:
		return
	_show_hint()

func _on_mouse_exited() -> void:
	if not enabled:
		return
	_hide_hint()

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_clicked()

func _on_clicked() -> void:
	"""玩家点击了此物体"""
	_interaction_count += 1

	# 播放视觉反馈
	match visual_effect:
		"pulse":
			_play_pulse()
		"glow":
			_play_glow()
		"bounce":
			_play_bounce()
		"color_shift":
			_play_color_shift()

	# 显示通用点击反馈（没有关键词触发时的 fallback）
	if interaction_keywords.is_empty():
		_show_click_feedback()

func check_keyword_match(text: String) -> String:
	"""
	检查玩家说的话是否匹配此物体的关键词。
	返回匹配的关键词，未匹配返回空字符串。
	"""
	if not enabled or interaction_keywords.is_empty():
		return ""

	# 冷却检查
	var now = Time.get_unix_time_from_system()
	if now - _last_interaction_time < cooldown_seconds:
		return ""

	var lower_text = text.to_lower()

	for keyword in interaction_keywords:
		if lower_text.contains(keyword.to_lower()):
			_last_interaction_time = now
			_trigger_interaction(keyword)
			return keyword

	return ""

func _trigger_interaction(keyword: String) -> void:
	"""触发关键词交互"""
	_interaction_count += 1
	interacted.emit(object_id, keyword)

	# 显示响应文本
	var text = response_text_zh if GameManager.current_lang == "zh" else response_text_en

	if not text.is_empty():
		_show_response(text)

	# 视觉反馈 - 使用 VFXManager
	_play_vfx_feedback()

	# 首次激活标记
	if not is_activated:
		is_activated = true
		activated.emit(object_id)

func _play_pulse() -> void:
	if not _has_sprite():
		return
	var sprite = _get_sprite()
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.15)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)
		UITweenManager.register_tween("vfx", tween)

func _play_glow() -> void:
	if not _has_sprite():
		return
	var sprite = _get_sprite()
	if sprite:
		var original_color = sprite.color
		var glow_color = Color(original_color.r, original_color.g, original_color.b, 0.5)
		var tween = create_tween()
		tween.tween_property(sprite, "color", glow_color, 0.3)
		tween.tween_property(sprite, "color", original_color, 0.5)
		UITweenManager.register_tween("vfx", tween)

func _play_bounce() -> void:
	var node = self as Node2D
	if node:
		var original_pos = node.position
		var tween = create_tween()
		tween.tween_property(node, "position", original_pos + Vector2(0, -10), 0.1)
		tween.tween_property(node, "position", original_pos, 0.15)
		UITweenManager.register_tween("vfx", tween)

func _play_color_shift() -> void:
	if not _has_sprite():
		return
	var sprite = _get_sprite()
	if sprite:
		var original = sprite.color
		var shifted = Color(original.g, original.b, original.r, original.a)
		var tween = create_tween()
		tween.tween_property(sprite, "color", shifted, 0.3)
		tween.tween_property(sprite, "color", original, 0.5)
		UITweenManager.register_tween("vfx", tween)

func _play_vfx_feedback() -> void:
	"""使用 VFXManager 播放交互视觉反馈"""
	match visual_effect:
		"none":
			pass
		"pulse":
			VFXManager.play_magic_activation(global_position, "pulse")
		"glow":
			var target: Node2D = _get_sprite()
			if target:
				VFXManager.play_shader_effect(target, "glow", {"color": Color(1.0, 1.0, 0.5, 0.5)})
		"bounce":
			VFXManager.play_magic_activation(global_position, "bounce")
		"color_shift":
			var target: Node2D = _get_sprite()
			if target:
				VFXManager.play_shader_effect(target, "color_shift", {"shift_amount": 0.3})

func _show_hint() -> void:
	if _hint_label:
		var hint_text = _get_hint_text()
		_hint_label.text = hint_text
		_hint_label.visible = true
		_position_hint()

func _hide_hint() -> void:
	if _hint_label:
		_hint_label.visible = false

func _show_response(text: String) -> void:
	"""显示交互响应文本"""
	if _hint_label:
		_hint_label.text = text
		_hint_label.visible = true
		_position_hint()

		# 淡出
		var tween = create_tween()
		tween.tween_interval(2.0)
		tween.tween_callback(func(): _hint_label.visible = false)
		UITweenManager.register_tween("ui_feedback", tween)

func _position_hint() -> void:
	if _hint_label:
		_hint_label.position = Vector2(-_hint_label.size.x / 2, -60)

func _has_sprite() -> bool:
	return _get_sprite() != null

func _get_sprite() -> Variant:
	"""尝试获取子节点中的 ColorRect 或 AnimatedSprite2D"""
	for child in get_children():
		if child is ColorRect or child is AnimatedSprite2D or child is Sprite2D:
			return child
	return null

func _show_click_feedback() -> void:
	"""通用点击反馈（无关键词匹配时）"""
	_show_response("✨")

func _get_hint_text() -> String:
	"""获取提示文本"""
	if interaction_keywords.is_empty():
		return "✨"
	var lang_zh = GameManager.current_lang == "zh"
	if lang_zh:
		return "说出: " + ", ".join(interaction_keywords.slice(0, 2))
	else:
		return "Say: " + ", ".join(interaction_keywords.slice(0, 2))

func get_interaction_count() -> int:
	"""获取交互次数"""
	return _interaction_count
