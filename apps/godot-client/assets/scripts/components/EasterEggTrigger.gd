## 彩蛋触发器
##
## 管理 L4 隐藏彩蛋的触发条件检测和响应。
## 支持的触发类型：
##   - sequence: 按顺序/无序说出一组词
##   - phrase: 说出特定短语（对特定 NPC）
##   - click_count: 点击特定目标 N 次
##   - timed_silence: 在场景中保持沉默 N 秒
##
extends Node

class_name EasterEggTrigger

# ——— 彩蛋数据 ———
class EasterEggConfig:
	var id: String
	var type: String  # sequence, phrase, click_count, timed_silence, achievement_chain
	var config: Dictionary
	var reward_text_zh: String
	var reward_text_en: String
	var spirit_hint: String  # 可能触发的词灵
	var triggered: bool = false
	var cooldown: float = 0.0  # 0 = 只触发一次

# ——— 内部状态 ———
var _eggs: Array[EasterEggConfig] = []
var _sequence_buffer: Array[String] = []
var _click_counts: Dictionary[String, int] = {}
var _silence_start: float = 0.0
var _last_trigger_time: Dictionary[String, float] = {}

signal easter_egg_triggered(egg_id: String, spirit_hint: String)

func _ready() -> void:
	_sequence_buffer.clear()

func register_egg(config: EasterEggConfig) -> void:
	"""注册一个彩蛋"""
	_eggs.append(config)

func register_eggs(eggs: Array[EasterEggConfig]) -> void:
	"""批量注册彩蛋"""
	for egg in eggs:
		_eggs.append(egg)

# ——— 外部调用接口 ———

func on_player_said(text: String) -> void:
	"""
	玩家说出文字后调用。
	检查 sequence、phrase、timed_silence 类型彩蛋。
	"""
	var lower = text.to_lower()

	# 重置沉默计时
	_silence_start = Time.get_unix_time_from_system()

	for egg in _eggs:
		if egg.triggered:
			if egg.cooldown > 0:
				var elapsed = Time.get_unix_time_from_system() - _last_trigger_time.get(egg.id, 0.0)
				if elapsed < egg.cooldown:
					continue
			else:
				continue

		match egg.type:
			"sequence":
				_check_sequence(egg, lower)
			"phrase":
				_check_phrase(egg, lower, text)

func on_npc_clicked(npc_id: String) -> void:
	"""NPC 被点击时调用。检查 click_count 类型彩蛋。"""
	if not _click_counts.has(npc_id):
		_click_counts[npc_id] = 0
	_click_counts[npc_id] += 1

	for egg in _eggs:
		if egg.triggered and egg.cooldown <= 0:
			continue

		if egg.type == "click_count":
			_check_click_count(egg, npc_id)

func on_scene_silent_for(duration: float) -> void:
	"""场景沉默达到指定时长时调用。"""
	for egg in _eggs:
		if egg.triggered and egg.cooldown <= 0:
			continue

		if egg.type == "timed_silence":
			if duration >= egg.config.get("duration", 10.0):
				_trigger_egg(egg)

# ——— 内部检查逻辑 ———

func _check_sequence(egg: EasterEggConfig, lower_text: String) -> void:
	"""检查 sequence 类型彩蛋"""
	var words: Array = egg.config.get("words", [])
	var ordered: bool = egg.config.get("ordered", false)

	# 将新词加入缓冲区
	for word in words:
		if lower_text.contains(word.to_lower()):
			if not _sequence_buffer.has(word):
				_sequence_buffer.append(word)

	# 检查是否收集了所有词
	var all_found = true
	for word in words:
		if not _sequence_buffer.has(word.to_lower()):
			all_found = false
			break

	if all_found and words.size() > 0:
		if ordered:
			# 检查顺序
			var ordered_correct = true
			var last_idx = -1
			for word in words:
				var idx = _sequence_buffer.find(word.to_lower())
				if idx <= last_idx:
					ordered_correct = false
					break
				last_idx = idx
			if ordered_correct:
				_trigger_egg(egg)
		else:
			_trigger_egg(egg)

func _check_phrase(egg: EasterEggConfig, lower_text: String, original_text: String) -> void:
	"""检查 phrase 类型彩蛋"""
	var target_phrase: String = egg.config.get("phrase", "").to_lower()
	var target_npc: String = egg.config.get("target_npc", "")

	# 如果指定了 NPC，检查当前 NPC
	if not target_npc.is_empty():
		if DialogueManager.has_method("get_current_npc_id"):
			var current_npc = DialogueManager.get_current_npc_id()
			if current_npc != target_npc:
				return

	if lower_text.contains(target_phrase):
		_trigger_egg(egg)

func _check_click_count(egg: EasterEggConfig, npc_id: String) -> void:
	"""检查 click_count 类型彩蛋"""
	var target: String = egg.config.get("target", "")
	var count: int = egg.config.get("count", 5)

	if target != npc_id:
		return

	if _click_counts.get(npc_id, 0) >= count:
		_trigger_egg(egg)

func _trigger_egg(egg: EasterEggConfig) -> void:
	"""触发彩蛋"""
	egg.triggered = true
	_last_trigger_time[egg.id] = Time.get_unix_time_from_system()

	var text = egg.reward_text_zh if GameManager.current_lang == "zh" else egg.reward_text_en

	print("[EasterEgg] Triggered: ", egg.id, " → ", text)

	# 显示庆祝文本
	if not text.is_empty():
		_show_celebration(text)

	# 触发信号（供 SpiritCollectionManager 等监听）
	easter_egg_triggered.emit(egg.id, egg.spirit_hint)

	# 清空缓冲区（sequence 类型）
	_sequence_buffer.clear()

func _show_celebration(text: String) -> void:
	"""显示彩蛋庆祝文本"""
	# 使用 CoachOverlay 显示
	if Engine.has_singleton("CoachOverlay"):
		var overlay = get_node_or_null("/root/Main/CoachOverlay")
		if overlay and overlay.has_method("show_hint"):
			overlay.show_hint(text, "excited")
			return

	# Fallback：创建临时 Label
	var label = Label.new()
	label.text = "🌟 " + text + " 🌟"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1, 0.84, 0, 1))
	label.add_theme_font_size_override("font_size", 24)
	label.set_anchors_preset(Control.PRESET_CENTER)

	get_tree().root.add_child(label)

	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

# ——— 工具方法 ———

func reset_all() -> void:
	"""重置所有彩蛋状态"""
	for egg in _eggs:
		egg.triggered = false
	_sequence_buffer.clear()
	_click_counts.clear()
	_last_trigger_time.clear()

func reset_egg(egg_id: String) -> void:
	"""重置单个彩蛋"""
	for egg in _eggs:
		if egg.id == egg_id:
			egg.triggered = false
			_last_trigger_time.erase(egg_id)
			break

func get_triggered_count() -> int:
	"""获取已触发彩蛋数量"""
	var count = 0
	for egg in _eggs:
		if egg.triggered:
			count += 1
	return count

func get_total_count() -> int:
	return _eggs.size()
