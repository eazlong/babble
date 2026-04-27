extends Node

const API_BASE_URL = "http://localhost:3000/api"

var http_request: HTTPRequest

signal services_ready()
signal tts_received(result: Dictionary)
signal asr_received(result: Dictionary)
signal dialogue_received(result: Dictionary)
signal api_error(error: String)

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func ping_services() -> void:
	var error = http_request.request(API_BASE_URL + "/ping", HTTPClient.METHOD_GET)
	if error != OK:
		api_error.emit("Failed to ping services: " + str(error))

func synthesize_tts(text: String, voice_id: String = "spirit", lang: String = "zh") -> void:
	var body = JSON.stringify({
		"text": text,
		"voice_id": voice_id,
		"lang": lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/tts/synthesize", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("TTS request failed: " + str(error))
		return
	await http_request.request_completed

func recognize_speech(audio_data: PackedByteArray, lang: String = "zh") -> void:
	var body = JSON.stringify({
		"audio_data": Marshalls.raw_to_base64(audio_data),
		"lang": lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/asr/recognize", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("ASR request failed: " + str(error))
		return
	await http_request.request_completed

func send_dialogue(user_text: String, npc_id: String, context: Array = []) -> void:
	var body = JSON.stringify({
		"user_text": user_text,
		"npc_id": npc_id,
		"context": context,
		"lang": GameManager.current_lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/dialogue/generate", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("Dialogue request failed: " + str(error))
		return
	await http_request.request_completed

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
	if result != HTTPRequest.RESULT_SUCCESS:
		api_error.emit("HTTP request failed with result: " + str(result))
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		api_error.emit("Failed to parse JSON response")
		return

	if json.has("audio_data"):
		tts_received.emit(json)
	elif json.has("text"):
		asr_received.emit(json)
	elif json.has("response"):
		dialogue_received.emit(json)
	else:
		services_ready.emit()