extends Node

var current_npc_id: String = ""
var dialogue_history: Array[Dictionary] = []
var dialogue_state: String = "idle"

signal dialogue_started(npc_id: String)
signal dialogue_ended()
signal player_response_ready(text: String)
signal npc_response_ready(response: String)

func _ready() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.dialogue_received.connect(_on_dialogue_received)
	HybridAPI.tts_received.connect(_on_tts_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)

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

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if dialogue_state != "active":
		return

	dialogue_state = "waiting_response"
	DialogueBox.hide_voice_listening()

	var result = await HybridAPI.process_voice_dialogue(audio_data, current_npc_id, GameManager.current_lang)

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

func _on_asr_received(result: Dictionary) -> void:
	pass

func _on_dialogue_received(result: Dictionary) -> void:
	pass

func _on_tts_received(result: Dictionary) -> void:
	pass

func end_dialogue() -> void:
	dialogue_state = "idle"
	VoicePipeline.stop_listening()
	DialogueBox.hide_message()
	dialogue_ended.emit()

	GameManager.completed_dialogues.append(current_npc_id)
	GameManager.save_progress()