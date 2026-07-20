## 蜃影客栈首次介绍场景
##
## 语音推进的导览场景：阵法房间建立主线，玩家房间开启词灵书阁，
## 衣橱和客房只做预告，避免首次进入时信息过载。
extends Node2D

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")
const VoiceFailureInterventionScript = preload("res://assets/scripts/components/voice/VoiceFailureIntervention.gd")

enum InnIntroState {
	ENTRY,
	FORMATION_ROOM,
	PLAYER_ROOM,
	AWAIT_BOOKSHELF_CALL,
	WORD_SPIRIT_LIBRARY,
	WARDROBE_PREVIEW,
	GUEST_ROOM_PREVIEW,
	SUMMARY,
	COMPLETED
}

const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
const MAX_RECORD_DURATION: float = 8.0
const SILENCE_HINT_DELAY: float = 5.0
const COACH_SILENCE_MS: int = 15000
const COACH_RESPONSE_TIMEOUT: float = 8.0
const TARGET_SCENE_PATH: String = "res://assets/scenes/ChangAnMarket.tscn"
const VIEW_SIZE: Vector2 = Vector2(1920, 1080)

const HALL_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_hall_bg.png")
const FORMATION_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_formation_room_bg.png")
const PLAYER_ROOM_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_player_room_bg.png")
const WORD_SPIRIT_LIBRARY_BACKGROUND = preload("res://assets/textures/backgrounds/word_spirit_library_bg.png")
const GUEST_ROOM_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_guest_room_bg.png")
const ARTIFACT_SEAT_EMPTY = preload("res://assets/textures/objects/inn/artifact_seat_empty.png")
const ARTIFACT_FIRST_LIGHT = preload("res://assets/textures/objects/inn/artifact_first_light.png")
const BOOKSHELF_CLOSED = preload("res://assets/textures/objects/inn/bookshelf_closed.png")
const BOOKSHELF_AWAKE = preload("res://assets/textures/objects/inn/bookshelf_awake.png")
const WARDROBE_EMPTY = preload("res://assets/textures/objects/inn/wardrobe_empty.png")
const WORD_SPIRIT_HELLO = preload("res://assets/textures/objects/inn/word_spirit_hello.png")
const GUEST_ROOM_DISTANT_LIGHT = preload("res://assets/textures/objects/inn/guest_room_distant_light.png")

@onready var feifei: FeifeiShoulder = $FeifeiLayer/FeifeiShoulder
@onready var mic_button: Control = $MicLayer/MicButton
@onready var quest_label: Label = $HUDLayer/QuestTracker/QuestLabel

var state: InnIntroState = InnIntroState.ENTRY
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
var voice_failure_intervention: VoiceFailureIntervention
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0

var world_layer: CanvasLayer
var visual_root: Control
var hall_view: Control
var formation_view: Control
var player_room_view: Control
var library_view: Control
var guest_view: Control
var fade_overlay: ColorRect
var first_light: TextureRect
var bookshelf_closed: TextureRect
var bookshelf_awake: TextureRect
var wardrobe_empty: TextureRect

func _ready() -> void:
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint("MirageInnIntroduction")
	_load_dialogue_flows()
	_build_visuals()
	_setup_voice_failure_intervention()
	_connect_runtime_signals()
	if mic_button:
		mic_button.visible = false
	_start_intro()

func _process(delta: float) -> void:
	_animate_first_light(delta)
	if not voice_listening:
		return

	var voice_pipeline: Variant = _voice_pipeline()
	if not voice_pipeline:
		return

	if voice_pipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
		if record_duration > MAX_RECORD_DURATION:
			voice_pipeline.stop_listening()
			_stop_voice_listening()
	else:
		silence_timer += delta
		record_duration = 0.0
		if silence_timer > SILENCE_HINT_DELAY:
			silence_timer = 0.0
			await _handle_voice_attempt_failed("silence")

func _start_intro() -> void:
	await get_tree().create_timer(0.35).timeout
	if feifei:
		feifei.visible = true
		await feifei.play_entry_fly_in()
		await feifei.settle_to_shoulder()

	state = InnIntroState.ENTRY
	_set_quest_text(_loc("quest_entry"))
	await _show_view(hall_view)
	await _speak_flow("inn_introduction.entry", 2.0)

	state = InnIntroState.FORMATION_ROOM
	_set_quest_text(_loc("quest_formation"))
	await _show_view(formation_view)
	await _speak_flow("inn_introduction.formation_room", 2.0)

	state = InnIntroState.PLAYER_ROOM
	_set_quest_text(_loc("quest_player_room"))
	await _show_view(player_room_view)
	await _speak_flow("inn_introduction.player_room", 2.0)

	state = InnIntroState.AWAIT_BOOKSHELF_CALL
	_set_quest_text(_loc("quest_bookshelf"))
	await _speak_flow("inn_introduction.bookshelf_voice_prompt", 2.0)
	_start_voice_listening()

func _continue_after_bookshelf_call() -> void:
	_stop_voice_listening()
	if feifei:
		feifei.play_happy()
	await _speak_flow("inn_introduction.bookshelf_opened", 1.5)

	state = InnIntroState.WORD_SPIRIT_LIBRARY
	_set_quest_text(_loc("quest_library"))
	await _show_view(library_view)
	await _speak_flow("inn_introduction.word_spirit_library", 2.0, {
		"word_text": "hello",
	})

	state = InnIntroState.WARDROBE_PREVIEW
	_set_quest_text(_loc("quest_wardrobe"))
	await _show_view(player_room_view)
	await _focus_wardrobe()
	await _speak_flow("inn_introduction.wardrobe_preview", 2.0)

	state = InnIntroState.GUEST_ROOM_PREVIEW
	_set_quest_text(_loc("quest_guest_room"))
	await _show_view(guest_view)
	await _speak_flow("inn_introduction.guest_room_preview", 2.0)

	state = InnIntroState.SUMMARY
	_set_quest_text(_loc("quest_summary"))
	await _show_view(hall_view)
	await _speak_flow("inn_introduction.summary", 2.0)
	await _complete_intro()

func _complete_intro() -> void:
	state = InnIntroState.COMPLETED
	_set_quest_text(_loc("quest_complete"))
	var manager: Variant = _game_manager()
	if manager:
		if not manager.unlocked_areas.has("MirageInnIntroduction"):
			manager.unlocked_areas.append("MirageInnIntroduction")
		if not manager.unlocked_areas.has("ChangAnMarket"):
			manager.unlocked_areas.append("ChangAnMarket")
		if not manager.completed_dialogues.has("mirage_inn_introduction_complete"):
			manager.completed_dialogues.append("mirage_inn_introduction_complete")
		manager.set_checkpoint("ChangAnMarket")

	await _fade_to_black()
	var change_result := get_tree().change_scene_to_file(TARGET_SCENE_PATH)
	if change_result != OK:
		push_error("[MirageInnIntroduction] Failed to change to ChangAnMarket: %s" % error_string(change_result))

func _build_visuals() -> void:
	world_layer = CanvasLayer.new()
	world_layer.name = "WorldLayer"
	world_layer.layer = 0
	add_child(world_layer)
	move_child(world_layer, 0)

	visual_root = Control.new()
	visual_root.name = "VisualRoot"
	visual_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_layer.add_child(visual_root)

	hall_view = _build_hall_view()
	formation_view = _build_formation_view()
	player_room_view = _build_player_room_view()
	library_view = _build_library_view()
	guest_view = _build_guest_view()

	for view in [hall_view, formation_view, player_room_view, library_view, guest_view]:
		view.visible = false
		view.modulate.a = 0.0
		visual_root.add_child(view)

	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color(0.04, 0.04, 0.05, 0.0)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$OverlayLayer.add_child(fade_overlay)

func _build_hall_view() -> Control:
	return _new_full_view("HallView", HALL_BACKGROUND)

func _build_formation_view() -> Control:
	var root := _new_full_view("FormationRoomView", FORMATION_BACKGROUND)
	var center := Vector2(960, 570)
	for i in range(6):
		var angle := TAU * float(i) / 6.0 - PI / 2.0
		var pos := center + Vector2(cos(angle), sin(angle)) * 255.0
		_add_texture(root, "ArtifactSeat%d" % (i + 1), ARTIFACT_SEAT_EMPTY, pos - Vector2(64, 64), Vector2(128, 128))

	first_light = _add_texture(root, "FirstArtifactLight", ARTIFACT_FIRST_LIGHT, center - Vector2(48, 48), Vector2(96, 96))
	return root

func _build_player_room_view() -> Control:
	var root := _new_full_view("PlayerRoomView", PLAYER_ROOM_BACKGROUND)
	bookshelf_closed = _add_texture(root, "BookshelfClosed", BOOKSHELF_CLOSED, Vector2(318, 315), Vector2(420, 520))
	bookshelf_awake = _add_texture(root, "BookshelfAwake", BOOKSHELF_AWAKE, Vector2(318, 315), Vector2(420, 520))
	bookshelf_awake.visible = false
	wardrobe_empty = _add_texture(root, "Wardrobe", WARDROBE_EMPTY, Vector2(1240, 335), Vector2(360, 460))
	return root

func _build_library_view() -> Control:
	var root := _new_full_view("WordSpiritLibraryView", WORD_SPIRIT_LIBRARY_BACKGROUND)
	_add_texture(root, "FirstWordSpirit", WORD_SPIRIT_HELLO, Vector2(832, 430), Vector2(256, 256))
	return root

func _build_guest_view() -> Control:
	var root := _new_full_view("GuestRoomView", GUEST_ROOM_BACKGROUND)
	_add_texture(root, "GuestRoomDistantLight", GUEST_ROOM_DISTANT_LIGHT, Vector2(750, 288), Vector2(420, 520))
	return root

func _new_full_view(view_name: String, texture: Texture2D) -> Control:
	var root := Control.new()
	root.name = view_name
	root.size = VIEW_SIZE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_texture(root, "Background", texture, Vector2.ZERO, VIEW_SIZE)
	return root

func _add_texture(parent: Control, node_name: String, texture: Texture2D, position: Vector2, size: Vector2) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.name = node_name
	texture_rect.texture = texture
	texture_rect.position = position
	texture_rect.size = size
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	parent.add_child(texture_rect)
	return texture_rect

func _show_view(target: Control) -> void:
	for child in visual_root.get_children():
		if child is Control and child != target:
			child.visible = false
	target.visible = true
	target.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(target, "modulate:a", 1.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _focus_wardrobe() -> void:
	if not wardrobe_empty:
		return
	var original_modulate: Color = wardrobe_empty.modulate
	var tween := create_tween()
	tween.tween_property(wardrobe_empty, "modulate", Color(1.22, 1.10, 0.78, 1.0), 0.35)
	tween.tween_property(wardrobe_empty, "modulate", original_modulate, 0.35)
	await tween.finished

func _animate_first_light(delta: float) -> void:
	if not first_light:
		return
	var pulse := 0.55 + sin(Time.get_ticks_msec() / 1000.0 * 3.0) * 0.30
	first_light.modulate.a = lerpf(first_light.modulate.a, pulse, delta * 4.0)

func _set_bookshelf_awake(is_awake: bool) -> void:
	if bookshelf_closed:
		bookshelf_closed.visible = not is_awake
	if bookshelf_awake:
		bookshelf_awake.visible = is_awake

func _fade_to_black() -> void:
	if not fade_overlay:
		return
	var tween := create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, 0.65).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _connect_runtime_signals() -> void:
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		if not voice_pipeline.voice_started.is_connected(_on_voice_started):
			voice_pipeline.voice_started.connect(_on_voice_started)
		if not voice_pipeline.voice_ended.is_connected(_on_voice_ended):
			voice_pipeline.voice_ended.connect(_on_voice_ended)
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api and not hybrid_api.asr_received.is_connected(_on_asr_received):
		hybrid_api.asr_received.connect(_on_asr_received)

func _load_dialogue_flows() -> void:
	if not dialogue_flow_loader.load_dialogue_flows():
		push_warning("[MirageInnIntroduction] Dialogue flow config loaded with errors.")

func _speak_flow(flow_id: String, fallback_seconds: float = 2.0, params: Dictionary = {}) -> void:
	var lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, _source_language_code(), params)
	for line in lines:
		await _say_dialogue_line(line, fallback_seconds)

func _say_dialogue_line(line: Dictionary, fallback_seconds: float = 2.0) -> void:
	var text: String = str(line.get("text", ""))
	var voice: String = str(line.get("voice", "spirit"))
	await _say_text(text, fallback_seconds, voice)

func _say_text(text: String, fallback_seconds: float = 2.0, voice: String = "spirit") -> void:
	if text.is_empty():
		return
	if feifei:
		feifei.show_hint(text, FeifeiShoulder.STATE_HINT, 0.0)
	voice_failure_intervention.add_turn("npc", text)
	var completed := await _synthesize_and_wait_for_tts(text, voice)
	if not completed and fallback_seconds > 0.0:
		push_warning("[MirageInnIntroduction] TTS playback wait timed out; using fallback pacing.")
		await get_tree().create_timer(fallback_seconds).timeout

func _synthesize_and_wait_for_tts(text: String, voice: String = "spirit", timeout: float = TTS_PLAYBACK_TIMEOUT) -> bool:
	var audio_manager: Variant = _audio_manager()
	var hybrid_api: Variant = _hybrid_api()
	if not audio_manager or not hybrid_api:
		return false

	var starting_playback_id: int = audio_manager.tts_playback_id
	var state_box := {
		"finished": false,
		"duration": 0.0,
	}
	var tts_finished_cb := func(playback_id: int, duration: float):
		if playback_id > starting_playback_id:
			state_box["finished"] = true
			state_box["duration"] = duration

	audio_manager.tts_playback_finished.connect(tts_finished_cb)
	hybrid_api.synthesize_tts(text, voice, _source_language_code())

	var elapsed := 0.0
	while not state_box["finished"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if audio_manager.tts_playback_finished.is_connected(tts_finished_cb):
		audio_manager.tts_playback_finished.disconnect(tts_finished_cb)

	if state_box["finished"]:
		var duration: float = state_box["duration"]
		await get_tree().create_timer(maxf(TTS_MIC_BUFFER_MIN, duration * 0.05)).timeout

	return state_box["finished"]

func _start_voice_listening() -> void:
	if voice_listening:
		return
	voice_listening = true
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = true
	_set_bookshelf_awake(true)
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.start_listening()

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = false
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.stop_listening()

func _on_voice_started() -> void:
	print("[MirageInnIntroduction] Voice started")

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if not voice_listening:
		return
	_stop_voice_listening()
	if feifei:
		feifei.show_hint(_loc("recognizing"), FeifeiShoulder.STATE_HINT, 0.0)
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		hybrid_api.recognize_speech(audio_data, _source_language_code(), _build_bookshelf_asr_context())

func _on_asr_received(result: Dictionary) -> void:
	if state != InnIntroState.AWAIT_BOOKSHELF_CALL:
		return
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	var text := _asr_text_for_bookshelf_call(result)
	if _is_bookshelf_call(text):
		voice_failure_intervention.reset_failures()
		voice_failure_intervention.add_turn("player", text)
		await _continue_after_bookshelf_call()
		return

	await _handle_voice_attempt_failed("wrong_answer")

func _handle_voice_attempt_failed(reason: String) -> void:
	if state != InnIntroState.AWAIT_BOOKSHELF_CALL:
		return
	if voice_failure_intervention.register_failure(reason):
		await get_tree().create_timer(0.45).timeout
		_start_voice_listening()
		return

	if feifei:
		feifei.show_hint(_loc("bookshelf_retry"), FeifeiShoulder.STATE_HINT, 0.0)
	await get_tree().create_timer(0.35).timeout
	_start_voice_listening()

func _is_bookshelf_call(text: String) -> bool:
	var lower := text.to_lower()
	return lower.contains("书架") or lower.contains("bookshelf") or lower.contains("book shelf")

func _set_quest_text(text: String) -> void:
	if quest_label:
		quest_label.text = text

func _loc(key: String) -> String:
	var is_zh := _source_language_code() == "zh"
	var strings := {
		"quest_entry": {"zh": "任务：进入蜃影客栈", "en": "Quest: Enter Mirage Inn"},
		"quest_formation": {"zh": "任务：查看阵法房间", "en": "Quest: Inspect the formation room"},
		"quest_player_room": {"zh": "任务：认识你的房间", "en": "Quest: Learn about your room"},
		"quest_bookshelf": {"zh": "任务：说“书架”", "en": "Quest: Say \"bookshelf\""},
		"quest_library": {"zh": "任务：进入词灵书阁", "en": "Quest: Enter the Word Spirit Library"},
		"quest_wardrobe": {"zh": "任务：查看衣橱", "en": "Quest: Preview the wardrobe"},
		"quest_guest_room": {"zh": "任务：查看客房", "en": "Quest: Preview the guest room"},
		"quest_summary": {"zh": "任务：记住客栈的三个房间", "en": "Quest: Remember the three rooms"},
		"quest_complete": {"zh": "客栈介绍完成：前往长安西市", "en": "Inn introduction complete: Go to Chang'an Market"},
		"bookshelf_retry": {"zh": "对着书架说“书架”，它就会听见你。", "en": "Say \"bookshelf\" to the bookshelf, and it will hear you."},
		"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
		"coach_waiting": {"zh": "别着急，腓腓来帮你。", "en": "No rush. Feifei will help."},
		"coach_fallback": {"zh": "我们慢慢来。请看着书架，清楚地说：“书架”。", "en": "Let's slow down. Look at the bookshelf and clearly say: \"bookshelf\"."},
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""

func _source_language_code() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.SOURCE_LANGUAGE_CODE)
	return "zh"

func _asr_text_for_bookshelf_call(result: Dictionary) -> String:
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		var extracted_answer := str(hybrid_api.get_asr_extracted_value(result, "answer", "")).strip_edges()
		if not extracted_answer.is_empty():
			return extracted_answer
		return str(hybrid_api.get_asr_corrected_text(result)).strip_edges()
	return str(result.get("text", "")).strip_edges()

func _setup_voice_failure_intervention() -> void:
	voice_failure_intervention = VoiceFailureInterventionScript.new()
	voice_failure_intervention.name = "VoiceFailureIntervention"
	add_child(voice_failure_intervention)
	voice_failure_intervention.set_feifei(feifei)
	voice_failure_intervention.set_failure_text_resolver(Callable(self, "_bookshelf_failure_turn_text"))
	voice_failure_intervention.set_tts_language_resolver(Callable(self, "_source_language_code"))
	voice_failure_intervention.configure({
		"scene_id": "mirage_inn_introduction",
		"npc_id": "feifei_mirage_inn",
		"waiting_text": _loc("coach_waiting"),
		"fallback_text": _loc("coach_fallback"),
		"silence_ms": COACH_SILENCE_MS,
		"response_timeout": COACH_RESPONSE_TIMEOUT,
	})
	voice_failure_intervention.start_session("mirage-inn-intro")

func _bookshelf_failure_turn_text(reason: String) -> String:
	match reason:
		"silence":
			return "[no_voice_detected] Player did not speak during the bookshelf voice prompt."
		"asr_error":
			return "[asr_error] Voice service returned an error during the bookshelf voice prompt."
		"wrong_answer":
			return "[wrong_answer] Player should say bookshelf/书架 but said something else."
		_:
			return "[voice_retry] Player needs help saying bookshelf/书架."

func _build_bookshelf_asr_context() -> Dictionary:
	return {
		"session_id": voice_failure_intervention.get_session_id(),
		"user_id": _player_name(),
		"npc_id": "feifei_mirage_inn",
		"scene_id": "mirage_inn_introduction",
		"npc_question": _loc("bookshelf_retry"),
		"expected_slots": [
			{
				"key": "answer",
				"type": "keyword",
				"description": "玩家对书架说出的唤醒词：书架/bookshelf",
			}
		],
		"expected_answer_type": "keyword",
		"candidate_answers": ["书架", "bookshelf", "book shelf"],
		"recent_turns": voice_failure_intervention.get_recent_turns(),
		"player_level": _player_level(),
		"language": _source_language_code(),
	}

func _player_name() -> String:
	var manager: Variant = _game_manager()
	if manager and str(manager.player_name) != "":
		return str(manager.player_name)
	return "anonymous"

func _player_level() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.player_cefr_level)
	return "pre_a1"

func _game_manager() -> Variant:
	return get_node_or_null("/root/GameManager")

func _voice_pipeline() -> Variant:
	return get_node_or_null("/root/VoicePipeline")

func _hybrid_api() -> Variant:
	return get_node_or_null("/root/HybridAPI")

func _audio_manager() -> Variant:
	return get_node_or_null("/root/AudioManager")
