extends Node

const API_BASE_URL = "http://localhost:8301"
const QUEST_SERVICE_URL = "http://localhost:8306"
const ASSESSMENT_SERVICE_URL = "http://localhost:8308"
const REWARD_SERVICE_URL = "http://localhost:8307"
const DEFAULT_ASR_TEST_ANSWERS: Array[String] = [
	"hello",
	"Carl",
	"yes I can",
	"hello",
	"big",
	"small",
	"red",
	"stand up",
	"open the book",
	"read aloud",
	"I like magic books",
	"I feel happy",
	"thank you Luna",
	"sunny",
	"rainy",
	"cloudy",
	"cat in the tree",
	"dog under the bridge",
	"bird in the bush",
	"plant red",
	"water blue",
	"grow yellow",
]

var http_request: HTTPRequest
var error_panel: PanelContainer
var error_label: Label
var error_timer: Timer

signal services_ready()
signal tts_received(result: Dictionary)
signal asr_received(result: Dictionary)
signal dialogue_received(result: Dictionary)
signal quest_status_received(result: Dictionary)
signal quest_report_received(result: Dictionary)
signal assessment_score_received(result: Dictionary)
signal api_error(error: String)

var coach_http_request: HTTPRequest
var tts_http_request: HTTPRequest
var parallel_asr_http_request: HTTPRequest
var _ping_in_progress: bool = false
var services_ready_done: bool = false
var asr_default_answer_test_enabled: bool = false
var asr_default_test_answers: Array[String] = DEFAULT_ASR_TEST_ANSWERS.duplicate()

# ——— 并行ASR状态追踪 ———
var _parallel_asr_pending: bool = false
var _parallel_asr_result: Dictionary = {}
var _parallel_asr_timeout_ms: int = 1500
var _asr_default_test_answer_index: int = 0

func _ready() -> void:
	_configure_asr_test_options()

	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	coach_http_request = HTTPRequest.new()
	add_child(coach_http_request)

	# TTS 独立请求，避免与 ASR/dialogue/quest 共享 HTTPRequest 导致 ERR_BUSY
	tts_http_request = HTTPRequest.new()
	add_child(tts_http_request)
	tts_http_request.request_completed.connect(_on_tts_request_completed)

	# 并行ASR独立请求
	parallel_asr_http_request = HTTPRequest.new()
	add_child(parallel_asr_http_request)
	parallel_asr_http_request.request_completed.connect(_on_parallel_asr_request_completed)

	# Create error notification UI
	_create_error_ui()
	api_error.connect(_on_api_error)

	# Auto-connect quest WebSocket when services are ready
	services_ready.connect(_on_services_ready)

func set_asr_default_answer_test_enabled(enabled: bool, answers: Array[String] = []) -> void:
	asr_default_answer_test_enabled = enabled
	_asr_default_test_answer_index = 0
	if not answers.is_empty():
		asr_default_test_answers = answers.duplicate()
	elif asr_default_test_answers.is_empty():
		asr_default_test_answers = DEFAULT_ASR_TEST_ANSWERS.duplicate()
	print("[HybridAPI] ASR default-answer test enabled: ", asr_default_answer_test_enabled)

func _configure_asr_test_options() -> void:
	_configure_asr_test_options_from_project_settings()
	_configure_asr_test_options_from_cmdline()

func _configure_asr_test_options_from_project_settings() -> void:
	var enabled := bool(ProjectSettings.get_setting("hybrid_api/asr_default_answer_test_enabled", false))
	var answers_value: Variant = ProjectSettings.get_setting("hybrid_api/asr_default_answers", PackedStringArray())
	var answers: Array[String] = _asr_answers_from_value(answers_value)
	if enabled:
		set_asr_default_answer_test_enabled(true, answers)

func _configure_asr_test_options_from_cmdline() -> void:
	var args: Array[String] = []
	for arg in OS.get_cmdline_args():
		args.append(arg)
	for arg in OS.get_cmdline_user_args():
		args.append(arg)

	var enabled := false
	var answers: Array[String] = []
	for arg in args:
		if arg == "--asr-default-answer-test":
			enabled = true
		elif arg.begins_with("--asr-default-answers="):
			enabled = true
			var raw_answers := arg.trim_prefix("--asr-default-answers=")
			for answer in raw_answers.split("|", false):
				var trimmed_answer := answer.strip_edges()
				if not trimmed_answer.is_empty():
					answers.append(trimmed_answer)

	if enabled:
		set_asr_default_answer_test_enabled(true, answers)

func _asr_answers_from_value(value: Variant) -> Array[String]:
	var answers: Array[String] = []
	if value is PackedStringArray:
		for answer in value:
			var trimmed_answer := str(answer).strip_edges()
			if not trimmed_answer.is_empty():
				answers.append(trimmed_answer)
	elif value is Array:
		for answer in value:
			var trimmed_answer := str(answer).strip_edges()
			if not trimmed_answer.is_empty():
				answers.append(trimmed_answer)
	return answers

func _apply_asr_default_answer_test(asr_result: Dictionary) -> Dictionary:
	if not asr_default_answer_test_enabled:
		return asr_result
	if asr_default_test_answers.is_empty():
		asr_default_test_answers = DEFAULT_ASR_TEST_ANSWERS.duplicate()

	var result := asr_result.duplicate(true)
	var actual_text := str(result.get("text", ""))
	var answer_index: int = mini(_asr_default_test_answer_index, asr_default_test_answers.size() - 1)
	var replacement_text: String = asr_default_test_answers[answer_index]
	_asr_default_test_answer_index += 1
	result["actual_text"] = actual_text
	result["text"] = replacement_text
	result["test_override"] = "asr_default_answer"
	result["test_answer_index"] = answer_index
	print("[HybridAPI] ASR default-answer test replaced '%s' with '%s'" % [actual_text, replacement_text])
	return result

func ping_services() -> void:
	_ping_in_progress = true
	var error = http_request.request(API_BASE_URL + "/ping", [], HTTPClient.METHOD_GET)
	if error != OK:
		_ping_in_progress = false
		push_error("[HybridAPI] Failed to ping services: " + str(error))

func synthesize_tts(text: String, voice_id: String = "spirit", lang: String = "zh") -> void:
	var body = JSON.stringify({
		"text": text,
		"voice_id": voice_id,
		"lang": lang
	})
	var headers = ["Content-Type: application/json"]
	var error = tts_http_request.request(API_BASE_URL + "/tts/synthesize", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		push_warning("[HybridAPI] TTS request deferred (HTTPRequest busy): ", error)

func recognize_speech(audio_data: PackedByteArray, lang: String = "en") -> void:
	print("[HybridAPI] recognize_speech: size=", audio_data.size(), " lang=", lang)
	var body = JSON.stringify({
		"audio_data": Marshalls.raw_to_base64(audio_data),
		"lang": lang
	})
	print("[HybridAPI] JSON body size: ", body.length())
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/api/v1/voice/asr/json", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		api_error.emit("ASR request failed: " + str(error))

## 并行ASR识别：同时调用英文+中文ASR，比较置信度选择结果
## 返回 {text, confidence, detected_language, processing_time_ms}
func recognize_speech_parallel(base64_audio: String, timeout_ms: int = 1500) -> Dictionary:
	_parallel_asr_timeout_ms = timeout_ms
	_parallel_asr_pending = true
	_parallel_asr_result = {}

	var body := JSON.stringify({
		"audio_data": base64_audio,
		"languages": ["en", "zh"],
		"parallel": true,
		"timeout_ms": timeout_ms
	})
	var headers := ["Content-Type: application/json"]
	var error := parallel_asr_http_request.request(
		API_BASE_URL + "/api/v1/dialogue/asr-parallel",
		headers, HTTPClient.METHOD_POST, body
	)
	if error != OK:
		_parallel_asr_pending = false
		push_warning("[HybridAPI] Parallel ASR request failed: %s" % str(error))
		return {
			"text": "",
			"confidence": 0.0,
			"detected_language": "unclear",
			"processing_time_ms": 0
		}

	# 等待回调或超时
	var elapsed: float = 0.0
	while _parallel_asr_pending and elapsed < (float(timeout_ms) / 1000.0 + 1.0):
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if _parallel_asr_pending:
		# 超时
		_parallel_asr_pending = false
		return {
			"text": "",
			"confidence": 0.0,
			"detected_language": "unclear",
			"processing_time_ms": timeout_ms
		}

	return _parallel_asr_result

## 分段TTS合成：根据语言分段调用不同TTS引擎
func synthesize_tts_segmented(
	text: String,
	voice_id: String = "spirit",
	segments: Array[Dictionary] = []
) -> Dictionary:
	var body := JSON.stringify({
		"text": text,
		"voice_id": voice_id,
		"segments": segments,
		"language_hint": "auto"
	})
	var headers := ["Content-Type: application/json"]
	var error := tts_http_request.request(
		API_BASE_URL + "/api/v1/dialogue/tts-segmented",
		headers, HTTPClient.METHOD_POST, body
	)
	if error != OK:
		push_warning("[HybridAPI] Segmented TTS request failed: %s" % str(error))
		return {"error": "request_failed"}

	# 等待TTS回调
	var result: Dictionary = await tts_received
	return result

## 对话处理：发送玩家输入到dialogue-service，获取NPC回复
func process_dialogue(
	player_input: String,
	detected_language: String,
	asr_confidence: float,
	npc_id: String,
	session_id: String,
	quest_context: String = ""
) -> Dictionary:
	var body := JSON.stringify({
		"session_id": session_id,
		"user_id": GameManager.player_name if GameManager.player_name != "" else "anonymous",
		"player_input": player_input,
		"detected_language": detected_language,
		"asr_confidence": asr_confidence,
		"npc_id": npc_id,
		"quest_context": quest_context
	})
	var headers := ["Content-Type: application/json"]
	var error := http_request.request(
		API_BASE_URL + "/api/v1/dialogue/process",
		headers, HTTPClient.METHOD_POST, body
	)
	if error != OK:
		push_warning("[HybridAPI] Dialogue process request failed: %s" % str(error))
		return {"error": "request_failed"}

	var result: Dictionary = await dialogue_received
	return result

func send_dialogue(user_text: String, npc_id: String, context: Array = []) -> void:
	var body = JSON.stringify({
		"user_text": user_text,
		"npc_id": npc_id,
		"context": context,
		"lang": GameManager.current_lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request("http://localhost:8302/api/v1/dialogue", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		api_error.emit("Dialogue request failed: " + str(error))

func process_voice_dialogue(audio_data: PackedByteArray, npc_id: String, lang: String = "zh") -> Dictionary:
	recognize_speech(audio_data, lang)
	var asr_result = await asr_received

	if asr_result.has("error"):
		return {"error": asr_result.error}

	var user_text = asr_result.get("text", "")

	send_dialogue(user_text, npc_id, DialogueManager.dialogue_history)
	var dialogue_result = await dialogue_received

	if dialogue_result.has("error"):
		return {"error": dialogue_result.error}

	var npc_response = dialogue_result.get("response", "")

	synthesize_tts(npc_response, npc_id, lang)
	var tts_result = await tts_received

	return {
		"user_text": user_text,
		"npc_response": npc_response,
		"audio_data": tts_result.get("audio_data", "")
	}

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _ping_in_progress:
		_ping_in_progress = false
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			_mark_services_ready()
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		api_error.emit("HTTP request failed with result: " + str(result))
		return

	# Check HTTP response code
	if response_code < 200 or response_code >= 300:
		api_error.emit("Server returned error code: " + str(response_code))
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		api_error.emit("Failed to parse JSON response")
		return

	if json.has("audio_data"):
		# Play TTS audio immediately via AudioManager
		var audio_data: String = json.get("audio_data", "")
		var format_type: String = json.get("format", "wav")
		AudioManager.play_audio_from_base64(audio_data, format_type)
		tts_received.emit(json)
	elif json.has("text"):
		var asr_result: Dictionary = _apply_asr_default_answer_test(json)
		print("[HybridAPI] ASR response: ", asr_result)
		asr_received.emit(asr_result)
	elif json.has("npc_text") or json.has("response"):
		# Normalize dialogue response format
		if json.has("npc_text") and not json.has("response"):
			json["response"] = json["npc_text"]
		dialogue_received.emit(json)
	elif json.has("completed_quest_ids") or json.has("lxp_earned"):
		# Quest service response — route by key fields
		if json.has("completed_quest_ids"):
			# GET /api/v1/quests/status response
			quest_status_received.emit(json)
		elif json.has("lxp_earned"):
			# POST /api/v1/quests/report response
			quest_report_received.emit(json)
	elif json.has("scores") and json.scores.has("accuracy"):
		# Assessment service response
		assessment_score_received.emit(json)
	else:
		_mark_services_ready()

func _mark_services_ready() -> void:
	if services_ready_done:
		return
	services_ready_done = true
	services_ready.emit()

func _on_tts_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""TTS 独立回调：只处理 TTS 响应"""
	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[HybridAPI] TTS HTTP request failed: result=", result, " response_code=", response_code)
		return

	if response_code < 200 or response_code >= 300:
		push_warning("[HybridAPI] TTS server returned: ", response_code)
		return

	var json_str = body.get_string_from_utf8()
	var json = JSON.parse_string(json_str)
	if json == null:
		push_error("[HybridAPI] Failed to parse TTS JSON response")
		return

	if json.has("audio_data"):
		var audio_data: String = json.get("audio_data", "")
		var format_type: String = json.get("format", "wav")
		AudioManager.play_audio_from_base64(audio_data, format_type)
		tts_received.emit(json)
	else:
		push_warning("[HybridAPI] TTS response missing audio_data: ", json)

func _on_parallel_asr_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	"""并行ASR独立回调"""
	if not _parallel_asr_pending:
		return

	if result != HTTPRequest.RESULT_SUCCESS:
		push_warning("[HybridAPI] Parallel ASR HTTP request failed: result=", result)
		_parallel_asr_pending = false
		_parallel_asr_result = {
			"text": "",
			"confidence": 0.0,
			"detected_language": "unclear",
			"processing_time_ms": 0
		}
		return

	if response_code < 200 or response_code >= 300:
		push_warning("[HybridAPI] Parallel ASR server returned: ", response_code)
		_parallel_asr_pending = false
		_parallel_asr_result = {
			"text": "",
			"confidence": 0.0,
			"detected_language": "unclear",
			"processing_time_ms": 0
		}
		return

	var json_str := body.get_string_from_utf8()
	var json = JSON.parse_string(json_str)
	if json == null:
		push_error("[HybridAPI] Failed to parse parallel ASR JSON response")
		_parallel_asr_pending = false
		_parallel_asr_result = {
			"text": "",
			"confidence": 0.0,
			"detected_language": "unclear",
			"processing_time_ms": 0
		}
		return

	_parallel_asr_pending = false
	_parallel_asr_result = {
		"text": json.get("text", ""),
		"confidence": json.get("confidence", 0.0),
		"detected_language": json.get("detected_language", "unclear"),
		"processing_time_ms": json.get("processing_time_ms", 0)
	}
	_parallel_asr_result = _apply_asr_default_answer_test(_parallel_asr_result)
	print("[HybridAPI] Parallel ASR result: ", _parallel_asr_result)

func publish_coach_silence_timeout(
	session_id: String,
	npc_id: String,
	silence_ms: int,
	player_level: String = "A1",
	recent_turns: Array = []
) -> void:
	var body = JSON.stringify({
		"event_type": "silence_timeout",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"silence_ms": silence_ms,
		"timestamp": int(Time.get_unix_time_from_system() * 1000),
		"player_level": player_level,
		"recent_turns": recent_turns,
	})
	var headers = ["Content-Type: application/json"]
	coach_http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)


func publish_coach_wake_request(
	session_id: String,
	npc_id: String,
	player_text: String,
	player_level: String = "A1",
	recent_turns: Array = []
) -> void:
	var body = JSON.stringify({
		"event_type": "wake_request",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"player_text": player_text,
		"timestamp": int(Time.get_unix_time_from_system() * 1000),
		"player_level": player_level,
		"recent_turns": recent_turns,
	})
	var headers = ["Content-Type: application/json"]
	coach_http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)


func publish_coach_dialogue_turn(
	session_id: String,
	npc_id: String,
	player_text: String,
	npc_response: String,
	language: String = "en",
	player_level: String = "A1",
	recent_turns: Array = []
) -> void:
	var body = JSON.stringify({
		"event_type": "dialogue_turn",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"player_text": player_text,
		"npc_response": npc_response,
		"language": language,
		"timestamp": int(Time.get_unix_time_from_system() * 1000),
		"player_level": player_level,
		"recent_turns": recent_turns,
	})
	var headers = ["Content-Type: application/json"]
	coach_http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)

func fetch_quest_status(scene_id: String, user_id: String = "anonymous") -> void:
	# 等待 services_ready，避免启动时 quest-service 尚未就绪导致 CANT_CONNECT (result=2)
	if not services_ready_done:
		await services_ready
	var query = "?user_id=%s&scene_id=%s" % [user_id.uri_encode(), scene_id.uri_encode()]
	http_request.request(
		QUEST_SERVICE_URL + "/api/v1/quests/status" + query,
		[], HTTPClient.METHOD_GET
	)

func report_quest_complete(
	quest_id: String,
	scene_id: String,
	scores: Dictionary,
	player_input: String = "",
	user_id: String = "anonymous"
) -> void:
	var body = JSON.stringify({
		"user_id": user_id,
		"quest_id": quest_id,
		"scene_id": scene_id,
		"scores": {
			"accuracy": scores.get("accuracy", 0),
			"fluency": scores.get("fluency", 0),
			"vocabulary": scores.get("vocabulary", 0)
		},
		"player_input": player_input
	})
	var headers = ["Content-Type: application/json"]
	http_request.request(
		QUEST_SERVICE_URL + "/api/v1/quests/report",
		headers, HTTPClient.METHOD_POST, body
	)

func assess_player_input(
	player_input: String,
	quest_id: String = "",
	scene_id: String = "",
	context: Dictionary = {},
	user_id: String = "anonymous"
) -> Dictionary:
	"""Call assessment-service to score player voice input.

	Returns {accuracy, fluency, vocabulary} or fallback defaults on error.
	"""
	var body = JSON.stringify({
		"user_id": user_id,
		"quest_id": quest_id,
		"scene_id": scene_id,
		"player_input": player_input,
		"context": context
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(
		ASSESSMENT_SERVICE_URL + "/api/v1/assessment/score",
		headers, HTTPClient.METHOD_POST, body
	)
	if error != OK:
		api_error.emit("Assessment request failed: " + str(error))
		return {"accuracy": 80, "fluency": 80, "vocabulary": 80}

	var result = await assessment_score_received
	if result.has("error") or not result.has("scores"):
		return {"accuracy": 80, "fluency": 80, "vocabulary": 80}

	return result.scores

func _create_error_ui() -> void:
	if error_label:
		return  # Already initialized (prevent duplicate creation)

	var canvas = CanvasLayer.new()
	add_child(canvas)

	error_panel = PanelContainer.new()
	error_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	error_panel.offset_top = 20
	error_panel.offset_bottom = 70
	error_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(error_panel)

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.8, 0.2, 0.2, 0.9)
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.set_content_margin_all(10)
	error_panel.add_theme_stylebox_override("panel", style_box)

	error_label = Label.new()
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.add_theme_color_override("font_color", Color.WHITE)
	error_label.add_theme_font_size_override("font_size", 18)
	error_panel.add_child(error_label)

	error_timer = Timer.new()
	error_timer.wait_time = 5.0
	error_timer.one_shot = true
	error_timer.timeout.connect(_hide_error)
	add_child(error_timer)

	error_label.visible = false
	error_panel.visible = false  # 面板默认隐藏，有错误时才显示

func _on_api_error(message: String) -> void:
	push_error("[HybridAPI] " + message)
	_show_error("⚠️ 连接服务器失败：" + message)

func _show_error(message: String) -> void:
	if is_instance_valid(error_label) and is_instance_valid(error_timer) and is_instance_valid(error_panel):
		error_label.text = message
		error_label.visible = true
		error_panel.visible = true
		if not error_timer.is_stopped():
			error_timer.stop()
		error_timer.start()

func _hide_error() -> void:
	if error_label:
		error_label.visible = false
	if error_panel:
		error_panel.visible = false

func _on_services_ready() -> void:
	# Connect quest WebSocket for real-time updates
	if has_node("/root/QuestWebSocket"):
		var quest_ws = get_node("/root/QuestWebSocket")
		var user_id = GameManager.player_name if GameManager.player_name != "" else "anonymous"
		quest_ws.connect_for_user(user_id)
		print("[HybridAPI] Quest WebSocket connecting for user: ", user_id)
