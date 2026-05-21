extends Node

var current_npc_id: String = ""
var dialogue_history: Array[Dictionary] = []
var dialogue_state: String = "idle"
var coach_session_id: String = ""
var silence_timer: Timer
var coach_overlay: CoachOverlay

signal dialogue_started(npc_id: String)
signal dialogue_ended()
signal player_response_ready(text: String)
signal npc_response_ready(response: String)

func _ready() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.dialogue_received.connect(_on_dialogue_received)
	HybridAPI.tts_received.connect(_on_tts_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	CoachClient.intervention_received.connect(_on_coach_intervention)

	silence_timer = Timer.new()
	silence_timer.one_shot = true
	silence_timer.timeout.connect(_on_silence_timeout)
	add_child(silence_timer)

func start_npc_dialogue(npc_id: String, greeting: String) -> void:
	current_npc_id = npc_id
	dialogue_history.clear()
	dialogue_state = "active"

	dialogue_started.emit(npc_id)

	DialogueBox.show_message(npc_id, greeting)

	HybridAPI.synthesize_tts(greeting, npc_id, GameManager.current_lang)
	await HybridAPI.tts_received

	await AudioManager.tts_finished
	VoicePipeline.start_listening()
	DialogueBox.show_voice_listening()

	coach_session_id = "dialogue-" + str(Time.get_unix_time_from_system())
	CoachClient.connect_for_session(coach_session_id)
	_reset_silence_watch()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if dialogue_state != "active":
		return

	dialogue_state = "waiting_response"
	DialogueBox.hide_voice_listening()

	var result = await HybridAPI.process_voice_dialogue(audio_data, current_npc_id, GameManager.current_lang)

	if _is_wake_request(result.get("user_text", "")):
		HybridAPI.publish_coach_wake_request(coach_session_id, current_npc_id, result.user_text)

	if result.has("error"):
		DialogueBox.show_message(current_npc_id, "抱歉，我没听清楚，请再说一次。")
		VoicePipeline.start_listening()
		dialogue_state = "active"
		return

	player_response_ready.emit(result.user_text)

	DialogueBox.show_message(current_npc_id, result.npc_response)
	npc_response_ready.emit(result.npc_response)

	if result.audio_data:
		AudioManager.play_audio_from_base64(result.audio_data)

	await AudioManager.tts_finished

	dialogue_state = "active"
	VoicePipeline.start_listening()
	DialogueBox.show_voice_listening()
	_reset_silence_watch()

func _on_coach_intervention(payload: Dictionary) -> void:
	if coach_overlay:
		coach_overlay.show_hint_for_duration(
			payload.get("text", ""),
			payload.get("emotion", "neutral"),
			payload.get("ttl_ms", 8000)
		)
	if payload.get("should_tts", false):
		var phrase = payload.get("repeat_phrase", payload.get("text", ""))
		HybridAPI.synthesize_tts(phrase, "spirit", GameManager.current_lang)

func _on_asr_received(result: Dictionary) -> void:
	pass

func _on_dialogue_received(result: Dictionary) -> void:
	pass

func _on_tts_received(result: Dictionary) -> void:
	pass

func end_dialogue() -> void:
	dialogue_state = "idle"
	silence_timer.stop()
	VoicePipeline.stop_listening()
	DialogueBox.hide_message()
	CoachClient.disconnect_socket()
	dialogue_ended.emit()

	GameManager.completed_dialogues.append(current_npc_id)
	GameManager.save_progress()

func _reset_silence_watch() -> void:
	silence_timer.start(15.0)

func _on_silence_timeout() -> void:
	if dialogue_state != "active" and dialogue_state != "waiting_response":
		return
	HybridAPI.publish_coach_silence_timeout(coach_session_id, current_npc_id, 15000)

func _is_wake_request(text: String) -> bool:
	var lower = text.to_lower()
	return lower.containsn("help") or lower.containsn("help me") or lower.containsn("帮帮我") or lower.containsn("帮助")
