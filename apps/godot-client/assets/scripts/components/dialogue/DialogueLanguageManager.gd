## 对话语言管理器
##
## 管理混合语言对话流程：
## - 并行ASR识别（同时调用英文+中文ASR，比较置信度）
## - 鼓励模板匹配（根据ASR结果和状态匹配响应模板）
## - 状态追踪（fallback_count, recent_attempts滚动窗口）
## - 语言比例动态调整（根据正确率调整中英比例）
## - 字符级语言检测（用于TTS分段合成）
##
## 信号流程：
##   玩家语音 → voice_ended → 并行ASR → asr_completed → 模板匹配
##   → response_selected → UI显示 + TTS播放
##
extends Node

# ——— 配置 ———
const TEMPLATES_PATH: String = "res://assets/resources/dialogue/encouragement_templates.json"
const ASR_TIMEOUT_MS: int = 1500  # 符合 core-loop 1.5s 预算
const CONFIDENCE_THRESHOLD_UNCLEAR: float = 0.4
const CONFIDENCE_MARGIN_SIGNIFICANT: float = 0.1
const RECENT_ATTEMPTS_WINDOW: int = 10

# ——— 语言比例规则（根据正确率） ———
const LANGUAGE_RATIOS: Array[Dictionary] = [
	{"accuracy_max": 0.4, "zh": 0.7, "en": 0.3},
	{"accuracy_max": 0.7, "zh": 0.4, "en": 0.6},
	{"accuracy_max": 0.9, "zh": 0.2, "en": 0.8},
	{"accuracy_max": 1.0, "zh": 0.05, "en": 0.95},
]

# ——— 状态 ———
var _templates: Array[Dictionary] = []
var _fallback_count: int = 0
var _recent_attempts: Array[Dictionary] = []  # [{success: bool, timestamp: float}]
var _session_id: String = ""
var _current_npc_id: String = ""
var _is_processing: bool = false

# ——— 信号 ———
signal asr_completed(result: Dictionary)
signal response_selected(template_id: String, response: Dictionary)
signal state_updated(fallback_count: int, accuracy: float)
signal dialogue_language_started(npc_id: String)
signal dialogue_language_ended()

# ——— 生命周期 ———

func _ready() -> void:
	_load_templates()
	_generate_session_id()
	_connect_signals()

func _connect_signals() -> void:
	VoicePipeline.voice_ended.connect(_on_voice_ended)

# ——— 模板加载 ———

func _load_templates() -> void:
	if not FileAccess.file_exists(TEMPLATES_PATH):
		push_warning("[DialogueLanguageManager] Templates file not found: %s" % TEMPLATES_PATH)
		return
	var file := FileAccess.open(TEMPLATES_PATH, FileAccess.READ)
	if file == null:
		push_warning("[DialogueLanguageManager] Failed to open templates file")
		return
	var json_str: String = file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		push_warning("[DialogueLanguageManager] Failed to parse templates JSON: %s" % json.get_error_message())
		return
	var data: Dictionary = json.data
	if data.has("templates"):
		_templates.assign(data["templates"])
		# 按优先级降序排序
		_templates.sort_custom(func(a, b): return a["priority"] > b["priority"])
	print("[DialogueLanguageManager] Loaded %d templates" % _templates.size())

# ——— 会话管理 ———

func _generate_session_id() -> void:
	_session_id = "dlg_%d" % int(Time.get_unix_time_from_system() * 1000)

func start_dialogue_session(npc_id: String) -> void:
	_current_npc_id = npc_id
	_fallback_count = 0
	_recent_attempts.clear()
	_generate_session_id()
	dialogue_language_started.emit(npc_id)
	print("[DialogueLanguageManager] Session started: %s for NPC: %s" % [_session_id, npc_id])

func end_dialogue_session() -> void:
	_current_npc_id = ""
	_fallback_count = 0
	_recent_attempts.clear()
	dialogue_language_ended.emit()
	print("[DialogueLanguageManager] Session ended: %s" % _session_id)

# ——— 核心流程：语音输入处理 ———

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if _is_processing:
		return
	if _current_npc_id.is_empty():
		return
	_is_processing = true
	_process_voice_input(audio_data)

func _process_voice_input(audio_data: PackedByteArray) -> void:
	# 并行ASR识别
	var asr_result: Dictionary = await _parallel_asr_recognize(audio_data)
	asr_completed.emit(asr_result)

	# 更新状态
	var detected_lang: String = asr_result.get("detected_language", "unknown")
	var confidence: float = asr_result.get("confidence", 0.0)
	var text: String = asr_result.get("text", "")
	var is_success: bool = _evaluate_success(text, detected_lang, confidence)
	_update_state_after_attempt(is_success)

	# 匹配鼓励模板
	var template_match: Dictionary = _match_encouragement_template(
		confidence, detected_lang, _fallback_count, ""
	)

	if template_match.is_empty():
		# 无匹配模板，使用默认响应
		template_match = {
			"id": "default",
			"response": {
				"npc_text": text,
				"spark_action": "idle",
				"difficulty_adjustment": "none",
				"audio_speed": 1.0
			}
		}

	# 替换占位符
	var response: Dictionary = template_match.get("response", {})
	var npc_text: String = response.get("npc_text", "")
	npc_text = npc_text.replace("{player_input}", text)
	npc_text = npc_text.replace("{demo}", _get_demo_text())
	npc_text = npc_text.replace("{target}", _get_target_text())
	response["npc_text"] = npc_text

	response_selected.emit(template_match.get("id", ""), response)
	_is_processing = false

# ——— 并行ASR识别 ———

func _parallel_asr_recognize(audio_data: PackedByteArray) -> Dictionary:
	# 同时调用英文和中文ASR
	var base64_audio: String = Marshalls.raw_to_base64(audio_data)

	# 使用HybridAPI的并行识别方法
	var result: Dictionary = await HybridAPI.recognize_speech_parallel(
		base64_audio, ASR_TIMEOUT_MS
	)
	return result

# ——— 成功评估 ———

func _evaluate_success(text: String, detected_lang: String, confidence: float) -> bool:
	# 高置信度英文 → 成功
	if detected_lang == "en" and confidence >= 0.7:
		return true
	# 中文 → 不算成功（需要引导说英文）
	if detected_lang == "zh":
		return false
	# 低置信度 → 失败
	if confidence < CONFIDENCE_THRESHOLD_UNCLEAR:
		return false
	return false

# ——— 状态更新 ———

func _update_state_after_attempt(success: bool) -> void:
	if success:
		_fallback_count = 0
	else:
		_fallback_count += 1

	# 滚动窗口：保留最近RECENT_ATTEMPTS_WINDOW条
	var timestamp: float = Time.get_unix_time_from_system()
	_recent_attempts.append({"success": success, "timestamp": timestamp})
	if _recent_attempts.size() > RECENT_ATTEMPTS_WINDOW:
		_recent_attempts = _recent_attempts.slice(-RECENT_ATTEMPTS_WINDOW)

	var accuracy: float = _calculate_accuracy()
	state_updated.emit(_fallback_count, accuracy)
	print("[DialogueLanguageManager] State updated: fallback=%d accuracy=%.2f" % [_fallback_count, accuracy])

func _calculate_accuracy() -> float:
	if _recent_attempts.is_empty():
		return 0.0
	var correct: int = 0
	for attempt in _recent_attempts:
		if attempt.get("success", false):
			correct += 1
	return float(correct) / float(_recent_attempts.size())

# ——— 语言比例计算 ———

func calculate_language_ratio() -> Dictionary:
	var accuracy: float = _calculate_accuracy()
	for ratio_rule in LANGUAGE_RATIOS:
		if accuracy < ratio_rule.get("accuracy_max", 1.0):
			return {"zh": ratio_rule["zh"], "en": ratio_rule["en"]}
	return {"zh": 0.05, "en": 0.95}

# ——— 鼓励模板匹配 ———

func _match_encouragement_template(
	confidence: float,
	detected_lang: String,
	fallback_count: int,
	error_type: String
) -> Dictionary:
	for template in _templates:
		if _template_matches(template, confidence, detected_lang, fallback_count, error_type):
			# 选择一个随机变体
			return _apply_variant(template)
	return {}

func _template_matches(
	template: Dictionary,
	confidence: float,
	detected_lang: String,
	fallback_count: int,
	error_type: String
) -> bool:
	var condition: Dictionary = template.get("condition", {})

	# ASR置信度条件
	if condition.has("asr_confidence"):
		var conf_range: Dictionary = condition["asr_confidence"]
		var min_conf: float = conf_range.get("min", 0.0)
		var max_conf: float = conf_range.get("max", 1.0)
		if confidence < min_conf or confidence > max_conf:
			return false

	# 检测语言条件
	if condition.has("detected_language"):
		var allowed_langs: Array = condition["detected_language"]
		if not allowed_langs.has(detected_lang):
			return false

	# 连续失败次数条件
	if condition.has("fallback_count"):
		var fc_range: Dictionary = condition["fallback_count"]
		var min_fc: int = fc_range.get("min", 0)
		var max_fc: int = fc_range.get("max", 999)
		if fallback_count < min_fc or fallback_count > max_fc:
			return false

	# 错误类型条件
	if condition.has("error_type"):
		var allowed_errors: Array = condition["error_type"]
		if not allowed_errors.has(error_type):
			return false

	return true

func _apply_variant(template: Dictionary) -> Dictionary:
	var result: Dictionary = template.duplicate(true)
	var variants: Array = result.get("variants", [])
	if variants.is_empty():
		return result
	# 随机选择一个变体
	var random_idx: int = randi() % variants.size()
	var selected_text: String = variants[random_idx]
	if result.has("response"):
		result["response"]["npc_text"] = selected_text
	return result

# ——— 字符级语言检测（用于TTS分段） ———

func detect_language_segments(text: String) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var current_lang: String = ""
	var current_text: String = ""

	for char in text:
		var char_lang: String = _detect_char_language(char)
		if char_lang.is_empty():
			# 标点/数字/空格，跟随当前语言
			if current_lang.is_empty():
				current_lang = "zh"  # 默认中文
			current_text += char
			continue

		if char_lang == current_lang:
			current_text += char
		else:
			if not current_text.is_empty():
				segments.append({"text": current_text.strip_edges(), "language": current_lang})
			current_lang = char_lang
			current_text = char

	if not current_text.is_empty():
		segments.append({"text": current_text.strip_edges(), "language": current_lang})

	return _merge_adjacent_segments(segments)

func _detect_char_language(char: String) -> String:
	# 中文字符范围（Unicode CJK Unified Ideographs）
	var code: int = char.unicode_at(0)
	if code >= 0x4E00 and code <= 0x9FFF:
		return "zh"
	# 英文字母
	if char.to_lower() != char.to_upper():
		return "en"
	# 标点/数字/空格
	return ""

func _merge_adjacent_segments(segments: Array[Dictionary]) -> Array[Dictionary]:
	if segments.is_empty():
		return segments
	var merged: Array[Dictionary] = [segments[0]]
	for i in range(1, segments.size()):
		var seg: Dictionary = segments[i]
		var prev: Dictionary = merged[merged.size() - 1]
		if seg["language"] == prev["language"]:
			prev["text"] += seg["text"]
		else:
			merged.append(seg)
	return merged

# ——— 占位符辅助 ———

func _get_demo_text() -> String:
	# 从场景配置获取当前示范文本
	# 实际使用时由SpiritForestController设置
	return "[demo]"

func _get_target_text() -> String:
	# 从场景配置获取当前目标文本
	return "[target]"

# ——— 公开API ———

func get_fallback_count() -> int:
	return _fallback_count

func get_accuracy() -> float:
	return _calculate_accuracy()

func get_session_id() -> String:
	return _session_id

func set_current_npc(npc_id: String) -> void:
	_current_npc_id = npc_id

func is_response_processing() -> bool:
	return _is_processing
