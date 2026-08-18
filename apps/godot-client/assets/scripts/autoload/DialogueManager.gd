extends Node

var current_npc_id: String = ""
var dialogue_history: Array[Dictionary] = []
var dialogue_state: String = "idle"
var coach_session_id: String = ""
var silence_timer: Timer
var coach_overlay: CoachOverlay
var coach_tracker: CoachContextTracker = CoachContextTracker.new()

# --- reconnection state ---
var _dialogue_context_snapshot: Dictionary = {}
var _is_recovering: bool = false

signal dialogue_started(npc_id: String)
signal dialogue_ended()
signal player_response_ready(text: String)
signal npc_response_ready(response: String)
signal dialogue_restored(context: Dictionary)

func _ready() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.dialogue_received.connect(_on_dialogue_received)
	HybridAPI.tts_received.connect(_on_tts_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	CoachClient.intervention_received.connect(_on_coach_intervention)

	# Spirit Collection Manager connection
	SpiritCollectionManager.spirit_unlocked.connect(_on_spirit_unlocked)

	# Listen for connection changes to handle reconnection
	if has_node("/root/QuestWebSocket"):
		var quest_ws = get_node("/root/QuestWebSocket")
		quest_ws.connection_changed.connect(_on_quest_connection_changed)

	silence_timer = Timer.new()
	silence_timer.one_shot = true
	silence_timer.wait_time = 15.0
	silence_timer.timeout.connect(_on_silence_timeout)
	add_child(silence_timer)

func start_npc_dialogue(npc_id: String, greeting: String) -> void:
	current_npc_id = npc_id
	dialogue_history.clear()
	coach_tracker.clear()
	dialogue_state = "active"

	dialogue_started.emit(npc_id)

	DialogueBox.show_message(npc_id, greeting)
	# NPC greeting counts as an NPC turn for the coach context
	coach_tracker.add_turn("npc", greeting)

	HybridAPI.synthesize_tts(greeting, npc_id, GameManager.current_lang)
	await HybridAPI.tts_received

	var tts_duration: float = await AudioManager.tts_finished
	# Small buffer after playback so residual echo doesn't leak into mic capture
	await get_tree().create_timer(max(0.3, tts_duration * 0.1)).timeout
	VoicePipeline.start_listening()
	DialogueBox.show_voice_listening()

	coach_session_id = "dialogue-" + str(Time.get_unix_time_from_system())
	CoachClient.connect_for_session(coach_session_id)
	_reset_silence_watch()
	
	# Save dialogue context for potential recovery
	_save_dialogue_context()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if dialogue_state != "active":
		return

	dialogue_state = "waiting_response"
	DialogueBox.hide_voice_listening()

	var result = await HybridAPI.process_voice_dialogue(
		audio_data,
		current_npc_id,
		GameManager.current_lang,
		_build_asr_context_for_current_turn()
	)

	# Check for spirit unlocks (LinguaQuest integration)
	_check_spirit_unlocks(result.get("user_text", ""), current_npc_id)

	if _is_wake_request(result.get("user_text", "")):
		HybridAPI.publish_coach_wake_request(
			coach_session_id,
			current_npc_id,
			result.user_text,
			GameManager.player_cefr_level,
			coach_tracker.get_recent_turns()
		)

	if result.has("error"):
		DialogueBox.show_message(current_npc_id, "抱歉，我没听清楚，请再说一次。")
		VoicePipeline.start_listening()
		dialogue_state = "active"
		return

	# Record this player turn in the coach context tracker
	coach_tracker.add_turn("player", result.user_text)

	player_response_ready.emit(result.user_text)

	DialogueBox.show_message(current_npc_id, result.npc_response)
	# Record the NPC response for coach context
	coach_tracker.add_turn("npc", result.npc_response)
	npc_response_ready.emit(result.npc_response)

	# Publish dialogue_turn to coach (for error detection / personalized response)
	HybridAPI.publish_coach_dialogue_turn(
		coach_session_id,
		current_npc_id,
		result.user_text,
		result.npc_response,
		GameManager.current_lang,
		GameManager.player_cefr_level,
		coach_tracker.get_recent_turns()
	)

	var tts_duration: float = 0.0
	if result.audio_data:
		AudioManager.play_audio_from_base64(result.audio_data)
		tts_duration = await AudioManager.tts_finished
	# Brief buffer so speaker tail doesn't get re-captured by mic
	await get_tree().create_timer(max(0.2, tts_duration * 0.05)).timeout

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

func _build_asr_context_for_current_turn() -> Dictionary:
	var recent_turns := coach_tracker.get_recent_turns()
	var npc_question := ""
	for i in range(recent_turns.size() - 1, -1, -1):
		var turn: Dictionary = recent_turns[i]
		if str(turn.get("speaker", "")) == "npc":
			npc_question = str(turn.get("text", ""))
			break

	return {
		"session_id": coach_session_id,
		"user_id": GameManager.player_name if GameManager.player_name != "" else "anonymous",
		"npc_id": current_npc_id,
		"scene_id": GameManager.current_scene,
		"npc_question": npc_question,
		"expected_slots": [
			{
				"key": "answer",
				"type": "string",
				"description": "玩家对 NPC 当前问题的回答",
			}
		],
		"expected_answer_type": "dialogue_answer",
		"candidate_answers": [],
		"recent_turns": recent_turns,
		"player_level": GameManager.player_cefr_level,
		"language": GameManager.current_lang,
	}

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
	coach_tracker.clear()
	dialogue_ended.emit()

	GameManager.completed_dialogues.append(current_npc_id)
	GameManager.save_progress()

func _reset_silence_watch() -> void:
	silence_timer.start(15.0)

func _on_silence_timeout() -> void:
	if dialogue_state != "active" and dialogue_state != "waiting_response":
		return
	HybridAPI.publish_coach_silence_timeout(
		coach_session_id,
		current_npc_id,
		15000,
		GameManager.player_cefr_level,
		coach_tracker.get_recent_turns()
	)

func _is_wake_request(text: String) -> bool:
	var lower = text.to_lower()
	return lower.containsn("help") or lower.containsn("help me") or lower.containsn("帮帮我") or lower.containsn("帮助")

# --- reconnection and context persistence ---

func _save_dialogue_context() -> void:
	"""Save current dialogue context for recovery after reconnect."""
	_dialogue_context_snapshot = {
		"npc_id": current_npc_id,
		"state": dialogue_state,
		"coach_session_id": coach_session_id,
		"history_length": dialogue_history.size(),
		"saved_at": Time.get_unix_time_from_system(),
		"last_messages": dialogue_history.slice(max(0, dialogue_history.size() - 5), dialogue_history.size()),
	}
	var prefs = ConfigFile.new()
	var save_path = "user://dialogue_context.cfg"
	prefs.set_value("dialogue", "context", JSON.stringify(_dialogue_context_snapshot))
	prefs.save(save_path)

func _load_dialogue_context() -> Dictionary:
	"""Load saved dialogue context."""
	var prefs = ConfigFile.new()
	var save_path = "user://dialogue_context.cfg"
	if prefs.load(save_path) == OK:
		var ctx_json = prefs.get_value("dialogue", "context", "")
		if ctx_json != "":
			var loaded = JSON.parse_string(ctx_json)
			if loaded is Dictionary:
				return loaded
	return {}

func _on_quest_connection_changed(is_connected: bool) -> void:
	"""Handle quest websocket connection changes."""
	if is_connected and _is_recovering:
		# We reconnected, now restore dialogue context
		_restore_dialogue_context()
	elif not is_connected and dialogue_state == "active":
		# Connection lost during active dialogue, mark for recovery
		_is_recovering = true
		_save_dialogue_context()
		print("[DialogueManager] Connection lost, dialogue context saved for recovery")

func _restore_dialogue_context() -> void:
	"""Restore dialogue context after reconnection."""
	var saved_context = _load_dialogue_context()
	if saved_context.is_empty():
		_is_recovering = false
		return
	
	_is_recovering = true
	var npc_id = saved_context.get("npc_id", "")
	var saved_state = saved_context.get("state", "idle")
	
	print("[DialogueManager] Restoring dialogue context for npc: ", npc_id, " state: ", saved_state)
	
	# Restore dialogue history
	var last_messages = saved_context.get("last_messages", [])
	for msg in last_messages:
		if not dialogue_history.has(msg):
			dialogue_history.append(msg)
	
	# Emit restore signal for UI to handle
	dialogue_restored.emit(saved_context)
	
	# Reset recovery flag
	_is_recovering = false
	
	# Reset silence watch if was active
	if saved_state == "active":
		_reset_silence_watch()

	# --- Spirit Collection Integration ---

func _check_spirit_unlocks(user_text: String, npc_id: String) -> void:
	"""
	Check for spirit unlock triggers in user voice input.
	Flow:
	1. Get all spirits associated with current NPC
	2. Check vocab_words for keyword matches
	3. Trigger unlock for first match found
	"""
	if user_text.is_empty():
		return

	var normalized_text = user_text.to_lower()

	# Get spirits for current NPC
	var available_spirits = SpiritDatabase.get_spirits_by_npc(npc_id)

	for spirit in available_spirits:
		var spirit_id: String = spirit.get("id", "")

		# Skip already unlocked
		if SpiritCollectionManager.is_spirit_unlocked(spirit_id):
			continue

		# Check vocab_words
		var vocab_words: Array = spirit.get("vocab_words", [])
		for word in vocab_words:
			if normalized_text.contains(word.to_lower()):
				# Trigger unlock
				SpiritCollectionManager.unlock_spirit(spirit_id, GameManager.current_scene, word)
				return  # One spirit per dialogue turn

func _on_spirit_unlocked(spirit_id: String, spirit_data: Dictionary) -> void:
	"""Handle spirit unlock event - pause dialogue and show unlock animation."""
	# Pause dialogue
	dialogue_state = "spirit_unlock"
	VoicePipeline.stop_listening()
	DialogueBox.hide_voice_listening()

	# Show unlock overlay (GameManager handles UI)
	GameManager.show_spirit_unlock(spirit_id)

func resume_after_spirit_unlock() -> void:
	"""Resume dialogue after spirit unlock animation completes."""
	if dialogue_state == "spirit_unlock":
		dialogue_state = "active"
		VoicePipeline.start_listening()
		DialogueBox.show_voice_listening()
		_reset_silence_watch()
