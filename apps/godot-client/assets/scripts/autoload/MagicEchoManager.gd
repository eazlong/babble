class_name MagicEchoManagerClass
extends Node

const DEFAULT_CHILD_ID: String = "local-child"
const SCENE_ID_MAP: Dictionary = {
	"BeginningFP": "beginning",
	"beginning": "beginning",
	"MirageInnIntroduction": "mirage_inn_introduction",
	"SpellLibrary": "spell_library",
	"spell_library": "spell_library",
	"RainbowGarden": "rainbow_garden",
	"rainbow_garden": "rainbow_garden",
	"ChangAnMarket": "chang_an_market_lesson_01",
	"chang_an_market_lesson_01": "chang_an_market_lesson_01",
	"WordSpiritLibraryArchiveHall": "word_spirit_library_archive_hall",
	"word_spirit_library_archive_hall": "word_spirit_library_archive_hall",
}
const LEARNING_SCENES: Array[String] = [
	"beginning",
	"mirage_inn_introduction",
	"spell_library",
	"rainbow_garden",
	"chang_an_market_lesson_01",
	"word_spirit_library_archive_hall",
]
const RECORDING_DIR: String = "user://magic_echo_recordings"
const RECORDING_FORMAT: String = "pcm_f32_stereo_44100"

var game_sessions: Dictionary = {}
var prompt_turns: Dictionary = {}
var interaction_attempts: Dictionary = {}
var timeline_events_by_session: Dictionary = {}
var active_session_by_child: Dictionary = {}
var attempt_id_by_child_and_local_id: Dictionary = {}
var recording_envelopes: Dictionary = {}
var pending_uploads: Dictionary = {}
var _next_id: int = 1
var _last_seen_scene_id: String = ""

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	_track_current_learning_scene()

func export_state() -> Dictionary:
	return {
		"game_sessions": game_sessions.duplicate(true),
		"prompt_turns": prompt_turns.duplicate(true),
		"interaction_attempts": interaction_attempts.duplicate(true),
		"timeline_events_by_session": timeline_events_by_session.duplicate(true),
		"active_session_by_child": active_session_by_child.duplicate(true),
		"attempt_id_by_child_and_local_id": attempt_id_by_child_and_local_id.duplicate(true),
		"recording_envelopes": recording_envelopes.duplicate(true),
		"pending_uploads": pending_uploads.duplicate(true),
		"last_seen_scene_id": _last_seen_scene_id,
		"next_id": _next_id,
	}

func import_state(data: Dictionary) -> void:
	game_sessions = data.get("game_sessions", {}).duplicate(true)
	prompt_turns = data.get("prompt_turns", {}).duplicate(true)
	interaction_attempts = data.get("interaction_attempts", {}).duplicate(true)
	timeline_events_by_session = data.get("timeline_events_by_session", {}).duplicate(true)
	active_session_by_child = data.get("active_session_by_child", {}).duplicate(true)
	attempt_id_by_child_and_local_id = data.get("attempt_id_by_child_and_local_id", {}).duplicate(true)
	recording_envelopes = data.get("recording_envelopes", {}).duplicate(true)
	pending_uploads = data.get("pending_uploads", {}).duplicate(true)
	_last_seen_scene_id = str(data.get("last_seen_scene_id", _last_seen_scene_id))
	_next_id = int(data.get("next_id", _next_id))

func enter_learning_scene(scene_id: String, child_id: String = DEFAULT_CHILD_ID) -> Dictionary:
	var normalized_scene_id := normalize_scene_id(scene_id)
	if not is_learning_scene(normalized_scene_id):
		return {}

	var active_session_id: String = str(active_session_by_child.get(child_id, ""))
	if not active_session_id.is_empty() and game_sessions.has(active_session_id):
		var active_session: Dictionary = game_sessions[active_session_id]
		if str(active_session.get("status", "")) == "active":
			if str(active_session.get("scene_id", "")) == normalized_scene_id:
				active_session["last_seen_at"] = _timestamp()
				game_sessions[active_session_id] = active_session
				return active_session.duplicate(true)
			_end_session(active_session_id, "scene_switch")

	var session_id := _new_id("game_session")
	var session := {
		"game_session_id": session_id,
		"child_id": child_id,
		"client_session_id": _new_id("client_session"),
		"scene_id": normalized_scene_id,
		"status": "active",
		"started_at": _timestamp(),
		"last_seen_at": _timestamp(),
		"ended_at": null,
		"end_reason": null,
	}
	game_sessions[session_id] = session
	timeline_events_by_session[session_id] = []
	active_session_by_child[child_id] = session_id
	_record_timeline_event(session_id, child_id, "session_started", "GameSession", session_id)
	_record_timeline_event(
		session_id,
		child_id,
		"scene_entered",
		"GameSession",
		session_id,
		{"scene_id": normalized_scene_id}
	)
	_create_scene_entry_trace(session_id, child_id, normalized_scene_id)
	return session.duplicate(true)

func create_prompt_turn(data: Dictionary) -> Dictionary:
	var game_session_id := str(data.get("game_session_id", ""))
	if game_session_id.is_empty() or not game_sessions.has(game_session_id):
		return {}

	var prompt_turn_id := str(data.get("prompt_turn_id", ""))
	if prompt_turn_id.is_empty():
		prompt_turn_id = _new_id("prompt_turn")

	var prompt := {
		"prompt_turn_id": prompt_turn_id,
		"game_session_id": game_session_id,
		"child_id": str(data.get("child_id", DEFAULT_CHILD_ID)),
		"scene_id": normalize_scene_id(str(data.get("scene_id", ""))),
		"quest_id": str(data.get("quest_id", "")),
		"content_id": str(data.get("content_id", "")),
		"content_version": int(data.get("content_version", 1)),
		"prompt_text_snapshot": str(data.get("prompt_text_snapshot", "")),
		"target_utterance_snapshot": str(data.get("target_utterance_snapshot", "")),
		"expected_answer_type": str(data.get("expected_answer_type", "short_answer")),
		"assessment_rule_version": str(data.get("assessment_rule_version", "v1")),
		"created_at": _timestamp(),
	}
	prompt_turns[prompt_turn_id] = prompt
	_record_timeline_event(
		prompt.get("game_session_id", ""),
		prompt.get("child_id", DEFAULT_CHILD_ID),
		"prompt_shown",
		"PromptTurn",
		prompt_turn_id,
		{
			"quest_id": prompt.get("quest_id", ""),
			"content_id": prompt.get("content_id", ""),
			"expected_answer_type": prompt.get("expected_answer_type", ""),
		}
	)
	return prompt.duplicate(true)

func create_interaction_attempt(data: Dictionary) -> Dictionary:
	var child_id := str(data.get("child_id", DEFAULT_CHILD_ID))
	var game_session_id := str(data.get("game_session_id", ""))
	var prompt_turn_id := str(data.get("prompt_turn_id", ""))
	if game_session_id.is_empty() or not game_sessions.has(game_session_id):
		return {}
	if prompt_turn_id.is_empty() or not prompt_turns.has(prompt_turn_id):
		return {}

	var local_attempt_id := str(data.get("local_attempt_id", ""))
	if local_attempt_id.is_empty():
		local_attempt_id = _new_id("local_attempt")
	var idempotency_key := "%s:%s" % [child_id, local_attempt_id]
	if attempt_id_by_child_and_local_id.has(idempotency_key):
		var existing_id: String = attempt_id_by_child_and_local_id[idempotency_key]
		if interaction_attempts.has(existing_id):
			return interaction_attempts[existing_id].duplicate(true)
		attempt_id_by_child_and_local_id.erase(idempotency_key)

	var attempt_id := _new_id("interaction_attempt")
	var attempt := {
		"interaction_attempt_id": attempt_id,
		"child_id": child_id,
		"game_session_id": game_session_id,
		"prompt_turn_id": prompt_turn_id,
		"local_attempt_id": local_attempt_id,
		"attempt_index": _next_attempt_index(prompt_turn_id),
		"recording_status": str(data.get("recording_status", "not_started")),
		"asr_status": str(data.get("asr_status", "not_started")),
		"realtime_assessment_status": str(data.get("realtime_assessment_status", "not_started")),
		"deep_assessment_status": str(data.get("deep_assessment_status", "not_started")),
		"created_at": _timestamp(),
		"deleted_sensitive_data_at": null,
	}
	interaction_attempts[attempt_id] = attempt
	attempt_id_by_child_and_local_id[idempotency_key] = attempt_id
	_record_timeline_event(game_session_id, child_id, "attempt_completed", "InteractionAttempt", attempt_id)
	return attempt.duplicate(true)

func query_game_session(game_session_id: String) -> Dictionary:
	if not game_sessions.has(game_session_id):
		return {}
	return {
		"game_session": game_sessions[game_session_id].duplicate(true),
		"prompt_turns": get_prompt_turns_for_session(game_session_id),
		"interaction_attempts": get_interaction_attempts_for_session(game_session_id),
		"timeline_events": get_timeline_events(game_session_id),
	}

func prepare_recording_attempt(data: Dictionary) -> Dictionary:
	var child_id := str(data.get("child_id", DEFAULT_CHILD_ID))
	var game_session_id := str(data.get("game_session_id", ""))
	var prompt_turn_id := str(data.get("prompt_turn_id", ""))
	if game_session_id.is_empty() or not game_sessions.has(game_session_id):
		return {}
	if prompt_turn_id.is_empty() or not prompt_turns.has(prompt_turn_id):
		return {}

	var local_attempt_id := str(data.get("local_attempt_id", ""))
	if local_attempt_id.is_empty():
		local_attempt_id = _new_id("local_attempt")
	var local_recording_id := str(data.get("local_recording_id", ""))
	if local_recording_id.is_empty():
		local_recording_id = _new_id("local_recording")

	var attempt := create_interaction_attempt({
		"child_id": child_id,
		"game_session_id": game_session_id,
		"prompt_turn_id": prompt_turn_id,
		"local_attempt_id": local_attempt_id,
		"recording_status": "recording_pending",
	})
	if attempt.is_empty():
		return {}

	var attempt_id := str(attempt.get("interaction_attempt_id", ""))
	_update_attempt_recording_status(attempt_id, "recording_pending")
	var envelope := {
		"local_attempt_id": local_attempt_id,
		"local_recording_id": local_recording_id,
		"interaction_attempt_id": attempt_id,
		"game_session_id": game_session_id,
		"prompt_turn_id": prompt_turn_id,
		"child_id": child_id,
		"attempt_type": str(data.get("attempt_type", "short_answer")),
		"status": "recording_pending",
		"recording_file_path": "",
		"format": RECORDING_FORMAT,
		"created_at": _timestamp(),
	}
	recording_envelopes[local_recording_id] = envelope
	_record_timeline_event(game_session_id, child_id, "recording_pending_created", "InteractionAttempt", attempt_id, {
		"local_recording_id": local_recording_id,
		"attempt_type": envelope.get("attempt_type", ""),
	})
	return envelope.duplicate(true)

func complete_recording_attempt(local_recording_id: String, audio_data: PackedByteArray, data: Dictionary = {}) -> Dictionary:
	if local_recording_id.is_empty() or not recording_envelopes.has(local_recording_id):
		return {}
	var envelope: Dictionary = recording_envelopes[local_recording_id]
	var completion_reason := str(data.get("completion_reason", "speech_detected"))
	var attempt_id := str(envelope.get("interaction_attempt_id", ""))
	var game_session_id := str(envelope.get("game_session_id", ""))
	var child_id := str(envelope.get("child_id", DEFAULT_CHILD_ID))

	if completion_reason == "no_speech_detected" or audio_data.is_empty():
		envelope["status"] = "no_speech_detected"
		envelope["completion_reason"] = "no_speech_detected"
		envelope["completed_at"] = _timestamp()
		recording_envelopes[local_recording_id] = envelope
		_update_attempt_recording_status(attempt_id, "no_speech_detected")
		_record_timeline_event(game_session_id, child_id, "no_speech_detected", "InteractionAttempt", attempt_id, {
			"local_recording_id": local_recording_id,
		})
		return envelope.duplicate(true)

	var file_path := _recording_file_path(local_recording_id)
	if not _write_recording_file(file_path, audio_data):
		return {}
	envelope["status"] = "pending_upload"
	envelope["completion_reason"] = completion_reason
	envelope["recording_file_path"] = file_path
	envelope["completed_at"] = _timestamp()
	recording_envelopes[local_recording_id] = envelope

	var upload := {
		"local_attempt_id": envelope.get("local_attempt_id", ""),
		"local_recording_id": local_recording_id,
		"interaction_attempt_id": attempt_id,
		"game_session_id": game_session_id,
		"prompt_turn_id": envelope.get("prompt_turn_id", ""),
		"child_id": child_id,
		"attempt_type": envelope.get("attempt_type", ""),
		"recording_file_path": file_path,
		"format": envelope.get("format", RECORDING_FORMAT),
		"status": "pending_upload",
		"completion_reason": completion_reason,
		"created_at": _timestamp(),
	}
	pending_uploads[local_recording_id] = upload
	_update_attempt_recording_status(attempt_id, "pending_upload")
	if completion_reason == "max_duration_reached":
		_record_timeline_event(game_session_id, child_id, "max_duration_reached", "InteractionAttempt", attempt_id, {
			"local_recording_id": local_recording_id,
		})
	_record_timeline_event(game_session_id, child_id, "recording_saved_locally", "InteractionAttempt", attempt_id, {
		"local_recording_id": local_recording_id,
		"recording_file_path": file_path,
	})
	return upload.duplicate(true)

func get_pending_uploads() -> Array:
	var uploads: Array = []
	for upload in pending_uploads.values():
		uploads.append(upload.duplicate(true))
	return uploads

func reconcile_local_recordings() -> Dictionary:
	_ensure_recording_dir()
	var known_paths := _known_recording_paths()
	var retained := 0
	var removed_orphans := 0
	var missing_referenced := 0
	for path in known_paths:
		if FileAccess.file_exists(path):
			retained += 1
		else:
			missing_referenced += 1

	var dir := DirAccess.open(RECORDING_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir():
				var path := RECORDING_DIR.path_join(file_name)
				if not known_paths.has(path) and dir.remove(file_name) == OK:
					removed_orphans += 1
			file_name = dir.get_next()
		dir.list_dir_end()
	return {
		"retained": retained,
		"removed_orphans": removed_orphans,
		"missing_referenced": missing_referenced,
	}

func get_active_session(child_id: String = DEFAULT_CHILD_ID) -> Dictionary:
	var session_id := str(active_session_by_child.get(child_id, ""))
	if session_id.is_empty() or not game_sessions.has(session_id):
		return {}
	var session: Dictionary = game_sessions[session_id]
	if str(session.get("status", "")) != "active":
		return {}
	return session.duplicate(true)

func get_prompt_turns_for_session(game_session_id: String) -> Array:
	var turns: Array = []
	for prompt in prompt_turns.values():
		if str(prompt.get("game_session_id", "")) == game_session_id:
			turns.append(prompt.duplicate(true))
	return turns

func get_interaction_attempts_for_session(game_session_id: String) -> Array:
	var attempts: Array = []
	for attempt in interaction_attempts.values():
		if str(attempt.get("game_session_id", "")) == game_session_id:
			attempts.append(attempt.duplicate(true))
	return attempts

func get_timeline_events(game_session_id: String) -> Array:
	var events: Array = []
	for event in timeline_events_by_session.get(game_session_id, []):
		events.append(event.duplicate(true))
	return events

func normalize_scene_id(scene_id: String) -> String:
	return str(SCENE_ID_MAP.get(scene_id, scene_id))

func is_learning_scene(scene_id: String) -> bool:
	return LEARNING_SCENES.has(normalize_scene_id(scene_id))

func _track_current_learning_scene() -> void:
	var game_manager := get_node_or_null("/root/GameManager")
	if not game_manager:
		return
	var scene_id := normalize_scene_id(str(game_manager.get("current_scene")))
	if scene_id == _last_seen_scene_id:
		return
	_last_seen_scene_id = scene_id
	if not is_learning_scene(scene_id):
		return
	enter_learning_scene(scene_id, _child_id_from_game_manager(game_manager))

func _child_id_from_game_manager(game_manager: Node) -> String:
	var player_name := str(game_manager.get("player_name"))
	if not player_name.is_empty():
		return player_name
	return DEFAULT_CHILD_ID

func _create_scene_entry_trace(game_session_id: String, child_id: String, scene_id: String) -> void:
	var prompt := create_prompt_turn({
		"child_id": child_id,
		"game_session_id": game_session_id,
		"scene_id": scene_id,
		"quest_id": "%s_entry" % scene_id,
		"content_id": "%s_entry_prompt" % scene_id,
		"content_version": 1,
		"prompt_text_snapshot": "Scene entry magic echo checkpoint",
		"target_utterance_snapshot": "",
		"expected_answer_type": "scene_entry",
		"assessment_rule_version": "v1",
	})
	if prompt.is_empty():
		return
	create_interaction_attempt({
		"child_id": child_id,
		"game_session_id": game_session_id,
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"local_attempt_id": "%s:%s:entry" % [game_session_id, scene_id],
		"recording_status": "not_started",
	})

func _end_session(game_session_id: String, reason: String) -> void:
	if not game_sessions.has(game_session_id):
		return
	var session: Dictionary = game_sessions[game_session_id]
	session["status"] = "ended"
	session["ended_at"] = _timestamp()
	session["end_reason"] = reason
	game_sessions[game_session_id] = session
	_record_timeline_event(
		game_session_id,
		str(session.get("child_id", DEFAULT_CHILD_ID)),
		"session_ended",
		"GameSession",
		game_session_id,
		{"end_reason": reason}
	)

func _record_timeline_event(
	game_session_id: String,
	child_id: String,
	event_type: String,
	related_entity_type: String = "",
	related_entity_id: String = "",
	payload_safe: Dictionary = {}
) -> Dictionary:
	if game_session_id.is_empty():
		return {}
	if not timeline_events_by_session.has(game_session_id):
		timeline_events_by_session[game_session_id] = []
	var events: Array = timeline_events_by_session[game_session_id]
	var sequence_no := events.size() + 1
	var event := {
		"timeline_event_id": _new_id("timeline_event"),
		"game_session_id": game_session_id,
		"child_id": child_id,
		"event_type": event_type,
		"sequence_no": sequence_no,
		"client_occurred_at": _timestamp(),
		"server_received_at": _timestamp(),
		"idempotency_key": "%s:%s:%s" % [game_session_id, event_type, sequence_no],
		"related_entity_type": related_entity_type,
		"related_entity_id": related_entity_id,
		"payload_version": 1,
		"payload_safe": payload_safe.duplicate(true),
	}
	events.append(event)
	timeline_events_by_session[game_session_id] = events
	return event.duplicate(true)

func _next_attempt_index(prompt_turn_id: String) -> int:
	var count := 0
	for attempt in interaction_attempts.values():
		if str(attempt.get("prompt_turn_id", "")) == prompt_turn_id:
			count += 1
	return count + 1

func _update_attempt_recording_status(interaction_attempt_id: String, status: String) -> void:
	if interaction_attempt_id.is_empty() or not interaction_attempts.has(interaction_attempt_id):
		return
	var attempt: Dictionary = interaction_attempts[interaction_attempt_id]
	attempt["recording_status"] = status
	attempt["updated_at"] = _timestamp()
	interaction_attempts[interaction_attempt_id] = attempt

func _recording_file_path(local_recording_id: String) -> String:
	return RECORDING_DIR.path_join("%s.pcm" % local_recording_id)

func _write_recording_file(path: String, audio_data: PackedByteArray) -> bool:
	_ensure_recording_dir()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[MagicEchoManager] Failed to open recording file: %s" % path)
		return false
	file.store_buffer(audio_data)
	file.close()
	return true

func _ensure_recording_dir() -> void:
	DirAccess.make_dir_recursive_absolute(RECORDING_DIR)

func _known_recording_paths() -> Array[String]:
	var paths: Array[String] = []
	for envelope in recording_envelopes.values():
		var path := str(envelope.get("recording_file_path", ""))
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	for upload in pending_uploads.values():
		var path := str(upload.get("recording_file_path", ""))
		if not path.is_empty() and not paths.has(path):
			paths.append(path)
	return paths

func _new_id(prefix: String) -> String:
	var id := "%s_%06d" % [prefix, _next_id]
	_next_id += 1
	return id

func _timestamp() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
