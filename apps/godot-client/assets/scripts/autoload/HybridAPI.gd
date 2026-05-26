extends Node

const API_BASE_URL = "http://localhost:8301"

var http_request: HTTPRequest
var error_label: Label
var error_timer: Timer

signal services_ready()
signal tts_received(result: Dictionary)
signal asr_received(result: Dictionary)
signal dialogue_received(result: Dictionary)
signal api_error(error: String)

var coach_http_request: HTTPRequest
var _ping_in_progress: bool = false

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

	coach_http_request = HTTPRequest.new()
	add_child(coach_http_request)

	# Create error notification UI
	_create_error_ui()
	api_error.connect(_on_api_error)

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
	var error = http_request.request(API_BASE_URL + "/tts/synthesize", headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		api_error.emit("TTS request failed: " + str(error))

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
			services_ready.emit()
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
		print("[HybridAPI] ASR response: ", json)
		asr_received.emit(json)
	elif json.has("npc_text") or json.has("response"):
		# Normalize dialogue response format
		if json.has("npc_text") and not json.has("response"):
			json["response"] = json["npc_text"]
		dialogue_received.emit(json)
	else:
		services_ready.emit()

func publish_coach_silence_timeout(session_id: String, npc_id: String, silence_ms: int) -> void:
	var body = JSON.stringify({
		"event_type": "silence_timeout",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"silence_ms": silence_ms,
		"timestamp": int(Time.get_unix_time_from_system() * 1000),
	})
	var headers = ["Content-Type: application/json"]
	coach_http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)

func publish_coach_wake_request(session_id: String, npc_id: String, player_text: String) -> void:
	var body = JSON.stringify({
		"event_type": "wake_request",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"player_text": player_text,
		"timestamp": int(Time.get_unix_time_from_system() * 1000),
	})
	var headers = ["Content-Type: application/json"]
	coach_http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)

func _create_error_ui() -> void:
	if error_label:
		return  # Already initialized (prevent duplicate creation)

	var canvas = CanvasLayer.new()
	add_child(canvas)

	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 20
	panel.offset_bottom = 70
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)

	var style_box = StyleBoxFlat.new()
	style_box.bg_color = Color(0.8, 0.2, 0.2, 0.9)
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	style_box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style_box)

	error_label = Label.new()
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	error_label.add_theme_color_override("font_color", Color.WHITE)
	error_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(error_label)

	error_timer = Timer.new()
	error_timer.wait_time = 5.0
	error_timer.one_shot = true
	error_timer.timeout.connect(_hide_error)
	add_child(error_timer)

	error_label.visible = false

func _on_api_error(message: String) -> void:
	push_error("[HybridAPI] " + message)
	_show_error("⚠️ 连接服务器失败：" + message)

func _show_error(message: String) -> void:
	if is_instance_valid(error_label) and is_instance_valid(error_timer):
		error_label.text = message
		error_label.visible = true
		if not error_timer.is_stopped():
			error_timer.stop()
		error_timer.start()

func _hide_error() -> void:
	if error_label:
		error_label.visible = false
