class_name VoiceFailureIntervention
extends Node

const CoachContextTrackerScript = preload("res://assets/scripts/components/coach/CoachContextTracker.gd")

const DEFAULT_THRESHOLD: int = 3
const DEFAULT_SILENCE_MS: int = 15000
const DEFAULT_RESPONSE_TIMEOUT: float = 8.0

var threshold: int = DEFAULT_THRESHOLD
var silence_ms: int = DEFAULT_SILENCE_MS
var response_timeout: float = DEFAULT_RESPONSE_TIMEOUT
var scene_id: String = ""
var npc_id: String = ""
var waiting_text: String = ""
var fallback_text: String = ""
var player_level: String = ""
var hint_state: String = "hint"

var hint_presenter: Variant
var tracker: Variant = CoachContextTrackerScript.new()
var failure_text_resolver: Callable
var tts_language_resolver: Callable

var _failure_count: int = 0
var _session_id: String = ""
var _intervention_pending: bool = false

signal intervention_requested(reason: String)
signal intervention_received(text: String)
signal intervention_timed_out()


func _exit_tree() -> void:
	var coach_client: Variant = _coach_client()
	if coach_client and coach_client.intervention_received.is_connected(_on_coach_intervention):
		coach_client.intervention_received.disconnect(_on_coach_intervention)


func configure(config: Dictionary) -> void:
	scene_id = str(config.get("scene_id", scene_id))
	npc_id = str(config.get("npc_id", npc_id))
	waiting_text = str(config.get("waiting_text", waiting_text))
	fallback_text = str(config.get("fallback_text", fallback_text))
	player_level = str(config.get("player_level", player_level))
	hint_state = str(config.get("hint_state", hint_state))
	threshold = int(config.get("threshold", threshold))
	silence_ms = int(config.get("silence_ms", silence_ms))
	response_timeout = float(config.get("response_timeout", response_timeout))


func set_feifei(value: Node) -> void:
	set_hint_presenter(value)


func set_hint_presenter(value: Variant) -> void:
	hint_presenter = value


func set_tracker(value: Variant) -> void:
	if value:
		tracker = value


func set_failure_text_resolver(value: Callable) -> void:
	failure_text_resolver = value


func set_tts_language_resolver(value: Callable) -> void:
	tts_language_resolver = value


func start_session(session_prefix: String = "") -> void:
	if not _session_id.is_empty():
		return
	var prefix := session_prefix
	if prefix.is_empty():
		prefix = scene_id if not scene_id.is_empty() else "voice"
	_session_id = "%s-%s" % [prefix, str(Time.get_unix_time_from_system())]
	if tracker and tracker.has_method("clear"):
		tracker.clear()
	var coach_client: Variant = _coach_client()
	if coach_client:
		if not coach_client.intervention_received.is_connected(_on_coach_intervention):
			coach_client.intervention_received.connect(_on_coach_intervention)
		coach_client.connect_for_session(_session_id)


func reset_failures() -> void:
	_failure_count = 0


func get_session_id() -> String:
	return _session_id


func get_recent_turns() -> Array[Dictionary]:
	if tracker and tracker.has_method("get_recent_turns"):
		return tracker.get_recent_turns()
	return []


func add_turn(speaker: String, text: String) -> void:
	if tracker and tracker.has_method("add_turn"):
		tracker.add_turn(speaker, text)


func register_failure(reason: String) -> bool:
	_failure_count += 1
	if _failure_count < threshold:
		return false

	_failure_count = 0
	_request_intervention(reason)
	return true


func _request_intervention(reason: String) -> void:
	if _intervention_pending:
		return
	_intervention_pending = true
	_show_hint(waiting_text)

	_publish_failure_context(reason)
	_watch_response_timeout()
	intervention_requested.emit(reason)


func _publish_failure_context(reason: String) -> void:
	if _session_id.is_empty():
		start_session()
	add_turn("player", _failure_turn_text(reason))

	var hybrid_api: Variant = _hybrid_api()
	if not hybrid_api:
		return
	hybrid_api.publish_coach_silence_timeout(
		_session_id,
		npc_id,
		silence_ms,
		_resolve_player_level(),
		get_recent_turns()
	)


func _on_coach_intervention(payload: Dictionary) -> void:
	if not _intervention_pending:
		return
	if str(payload.get("session_id", "")) != _session_id:
		return
	_intervention_pending = false

	var text := str(payload.get("text", "")).strip_edges()
	if text.is_empty():
		text = fallback_text
	_show_intervention_text(text)
	add_turn("npc", text)
	intervention_received.emit(text)

	if bool(payload.get("should_tts", false)):
		var phrase := str(payload.get("repeat_phrase", text))
		var hybrid_api: Variant = _hybrid_api()
		if hybrid_api:
			hybrid_api.synthesize_tts(phrase, "spirit", _resolve_tts_language())


func _watch_response_timeout() -> void:
	await get_tree().create_timer(response_timeout).timeout
	if not _intervention_pending:
		return
	_intervention_pending = false
	_show_intervention_text(fallback_text)
	intervention_timed_out.emit()


func _show_intervention_text(text: String) -> void:
	_show_hint(text)


func _show_hint(text: String) -> void:
	if text.is_empty() or not hint_presenter or not hint_presenter.has_method("show_hint"):
		return
	if hint_presenter is FeifeiShoulder or hint_presenter is FeifeiBody:
		hint_presenter.show_hint(text, hint_state, 0.0)
	else:
		hint_presenter.show_hint(text, hint_state)


func _failure_turn_text(reason: String) -> String:
	if failure_text_resolver.is_valid():
		return str(failure_text_resolver.call(reason))
	match reason:
		"silence":
			return "[no_voice_detected] Player did not speak during a voice prompt."
		"empty_asr":
			return "[empty_asr] Voice service returned no recognized text."
		"api_error":
			return "[api_error] Voice service failed during a voice prompt."
		"asr_timeout":
			return "[asr_timeout] Voice service timed out during a voice prompt."
		"asr_error":
			return "[asr_error] Voice service returned an error."
		"wrong_answer":
			return "[wrong_answer] Player tried but did not match the expected phrase."
		_:
			return "[voice_retry] Player needs help during a voice prompt."


func _resolve_player_level() -> String:
	if not player_level.is_empty():
		return player_level
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.player_cefr_level)
	return "pre_a1"


func _resolve_tts_language() -> String:
	if tts_language_resolver.is_valid():
		return str(tts_language_resolver.call())
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.SOURCE_LANGUAGE_CODE)
	return "zh"


func _game_manager() -> Variant:
	return get_node_or_null("/root/GameManager")


func _hybrid_api() -> Variant:
	return get_node_or_null("/root/HybridAPI")


func _coach_client() -> Variant:
	return get_node_or_null("/root/CoachClient")
