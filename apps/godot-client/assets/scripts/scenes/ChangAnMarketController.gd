## 长安西市第一课：西市晨钟，初入长安
##
## Implements the P1 gameplay spec for Grade 4 Unit 1 "Meeting new people":
## voice greeting, name registration, sit interaction, her/his name contrast,
## classmate bond, Baize recognition, and afternoon review.
extends Node2D

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")
const LessonResponseMatcherScript = preload("res://assets/scripts/core/lesson_response_matcher.gd")
const VoiceFailureInterventionScript = preload("res://assets/scripts/components/voice/VoiceFailureIntervention.gd")

const CONFIG_PATH: String = "res://assets/resources/scene_configs/chang_an_market_lesson_01.json"
const VIEW_SIZE: Vector2 = Vector2(1920, 1080)
const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
const MAX_RECORD_DURATION: float = 8.0
const SILENCE_HINT_DELAY: float = 5.0
const COACH_SILENCE_MS: int = 15000
const COACH_RESPONSE_TIMEOUT: float = 8.0
# 除腓腓教练外，其它 NPC 只能说目标语言；腓腓可用源语言（中文）做提示与引导。
const FEIFEI_SPEAKER: String = "feifei"

enum LessonState {
	LOADING,
	PLAYING_FLOW,
	AWAITING_VOICE,
	COMPLETED
}

@onready var feifei: FeifeiShoulder = get_node_or_null("FeifeiLayer/FeifeiShoulder")
@onready var mic_button: Control = get_node_or_null("MicLayer/MicButton")
@onready var quest_label: Label = get_node_or_null("HUDLayer/QuestTracker/QuestLabel")

var state: LessonState = LessonState.LOADING
var config: Dictionary = {}
var steps: Array = []
var current_step_index: int = -1
var current_step: Dictionary = {}
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
var voice_failure_intervention: VoiceFailureIntervention
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
var asr_request_active: bool = false
var earned_words: Array[String] = []

var world_layer: CanvasLayer
var visual_root: Control
var market_view: Control
var inn_review_view: Control
var mist_overlay: ColorRect
var step_title_label: Label
var npc_status_label: Label
var word_spirit_bar: HBoxContainer

func _ready() -> void:
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint("ChangAnMarket", not manager.is_test_mode_skip_auto_load_save())
	_load_config()
	_load_dialogue_flows()
	_build_visuals()
	_setup_voice_failure_intervention()
	_connect_runtime_signals()
	
	HybridAPI.set_asr_default_answer_test_enabled(true, "res://assets/test_audio/", ["good_morning.wav", "my_name_is_carl.wav", "sit_here.wav"])
	if mic_button:
		mic_button.visible = false
	_start_lesson()

func _process(delta: float) -> void:
	_animate_mist(delta)
	if not voice_listening:
		return
	var voice_pipeline: Variant = _voice_pipeline()
	if not voice_pipeline:
		return
	if voice_pipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
	else:
		silence_timer += delta
		record_duration = 0.0
		if silence_timer > SILENCE_HINT_DELAY:
			silence_timer = 0.0
			await _handle_voice_attempt_failed("silence")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER:
		if state == LessonState.AWAITING_VOICE:
			await _accept_current_voice_step("[debug accepted]")

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[ChangAnMarket] Failed to load config: %s" % CONFIG_PATH)
		config = {}
		steps = []
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		config = parsed
		steps = config.get("steps", [])
	else:
		push_error("[ChangAnMarket] Config root must be a JSON object.")
		config = {}
		steps = []

func _load_dialogue_flows() -> void:
	if not dialogue_flow_loader.load_dialogue_flows():
		push_warning("[ChangAnMarket] Dialogue flow config loaded with errors.")

func _start_lesson() -> void:
	if feifei:
		feifei.visible = true
		await feifei.play_entry_fly_in()
		await feifei.settle_to_shoulder()
	await _go_to_step(0)

func _go_to_step(index: int) -> void:
	if index >= steps.size():
		await _complete_lesson()
		return
	current_step_index = index
	current_step = steps[index]
	state = LessonState.PLAYING_FLOW
	_update_step_visuals()
	_set_quest_text(_loc(str(current_step.get("quest_key", ""))))
	await _speak_flow(str(current_step.get("flow_id", "")), 1.8)

	var step_type: String = str(current_step.get("type", "auto"))
	match step_type:
		"voice":
			state = LessonState.AWAITING_VOICE
			_start_voice_listening()
		_:
			await _reward_step_words()
			await _go_to_step(current_step_index + 1)

func _accept_current_voice_step(player_text: String) -> void:
	_stop_voice_listening()
	voice_failure_intervention.reset_failures()
	voice_failure_intervention.add_turn("player", player_text)
	await _reward_step_words()
	var success_flow_id: String = str(current_step.get("success_flow_id", ""))
	if not success_flow_id.is_empty():
		await _speak_flow(success_flow_id, 1.5)
	await _go_to_step(current_step_index + 1)

func _reward_step_words() -> void:
	var reward_words: Array = current_step.get("reward_words", [])
	for value in reward_words:
		var word: String = str(value)
		if word.is_empty():
			continue
		_unlock_word(word)
		await _show_word_spirit(word)

func _unlock_word(word: String) -> void:
	if not earned_words.has(word):
		earned_words.append(word)
	var manager: Variant = _game_manager()
	if manager:
		if not manager.vocabulary_learned.has(word):
			manager.vocabulary_learned.append(word)
		if not manager.unlocked_spirits.has(word):
			manager.unlocked_spirits.append(word)

func _complete_lesson() -> void:
	state = LessonState.COMPLETED
	_set_quest_text(_loc("quest_complete"))
	var manager: Variant = _game_manager()
	if manager:
		var completion_id: String = str(config.get("completion_dialogue_id", "chang_an_market_lesson_01_complete"))
		if not manager.completed_dialogues.has(completion_id):
			manager.completed_dialogues.append(completion_id)
		var next_unlock: String = str(config.get("next_unlock", ""))
		if not next_unlock.is_empty() and not manager.unlocked_areas.has(next_unlock):
			manager.unlocked_areas.append(next_unlock)
		manager.lxp_score += int(config.get("lxp_reward", 0))
		manager.save_progress()
	if feifei:
		feifei.play_happy()

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

func _start_voice_listening() -> void:
	if voice_listening:
		return
	voice_listening = true
	asr_request_active = false
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = true
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.start_listening()

func _stop_voice_listening() -> void:
	voice_listening = false
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = false
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.stop_listening()

func _on_voice_started() -> void:
	print("[ChangAnMarket] Voice started")

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if state != LessonState.AWAITING_VOICE or asr_request_active:
		return
	_stop_voice_listening()
	asr_request_active = true
	if feifei:
		feifei.show_hint(_loc("recognizing"), FeifeiShoulder.STATE_HINT, 0.0)
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		hybrid_api.recognize_speech(audio_data, _special_language_code(), _build_asr_context())

func _on_asr_received(result: Dictionary) -> void:
	if state != LessonState.AWAITING_VOICE:
		return
	asr_request_active = false
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	var text: String = _asr_text(result)
	var match_result: Dictionary = LessonResponseMatcherScript.evaluate(text, current_step.get("asr", {}))
	var tier: String = str(match_result.get("tier", "needs_help"))
	if tier == LessonResponseMatcherScript.RESULT_CLEAR or tier == LessonResponseMatcherScript.RESULT_UNDERSTANDABLE:
		await _accept_current_voice_step(text)
		return
	await _handle_voice_attempt_failed(str(match_result.get("reason", "wrong_answer")))

func _handle_voice_attempt_failed(reason: String) -> void:
	if state != LessonState.AWAITING_VOICE:
		return
	if voice_failure_intervention.register_failure(reason):
		await get_tree().create_timer(0.45).timeout
		_start_voice_listening()
		return
	var retry_flow_id: String = str(current_step.get("retry_flow_id", ""))
	if not retry_flow_id.is_empty():
		await _speak_flow(retry_flow_id, 1.2)
	await get_tree().create_timer(0.25).timeout
	_start_voice_listening()

func _build_asr_context() -> Dictionary:
	var expected: Dictionary = current_step.get("asr", {})
	var phrases: Array = expected.get("clear_phrases", []) + expected.get("acceptable_phrases", [])
	return {
		"session_id": voice_failure_intervention.get_session_id(),
		"user_id": _player_name(),
		"npc_id": "chang_an_market_lesson",
		"scene_id": str(config.get("scene_id", "chang_an_market_lesson_01")),
		"npc_question": _loc(str(current_step.get("quest_key", ""))),
		"expected_slots": [
			{
				"key": "answer",
				"type": "keyword",
				"description": "English lesson response for the current West Market step"
			}
		],
		"expected_answer_type": "keyword",
		"candidate_answers": phrases,
		"recent_turns": voice_failure_intervention.get_recent_turns(),
		"player_level": _player_level(),
		"language": _special_language_code()
	}

func _asr_text(result: Dictionary) -> String:
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		var extracted_answer := str(hybrid_api.get_asr_extracted_value(result, "answer", "")).strip_edges()
		if not extracted_answer.is_empty():
			return extracted_answer
		return str(hybrid_api.get_asr_corrected_text(result)).strip_edges()
	return str(result.get("text", "")).strip_edges()

func _speak_flow(flow_id: String, fallback_seconds: float = 1.8, params: Dictionary = {}) -> void:
	if flow_id.is_empty():
		return
	var merged_params: Dictionary = {
		"player_name": _player_name()
	}
	for key in params.keys():
		merged_params[key] = params[key]
	var source_lang: String = _source_language_code()
	var target_lang: String = _special_language_code()
	var source_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, source_lang, merged_params)
	if source_lang == target_lang:
		for line in source_lines:
			_set_speaker_focus(str(line.get("speaker", "")))
			await _say_dialogue_line(line, source_lang, fallback_seconds)
		return
	# 非腓腓 NPC 只说目标语言；腓腓可用源语言。两条列表同序，按说话人逐行选语言。
	var target_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, target_lang, merged_params)
	for i in range(source_lines.size()):
		var source_line: Dictionary = source_lines[i]
		var speaker: String = str(source_line.get("speaker", ""))
		var lang: String = source_lang if speaker == FEIFEI_SPEAKER else target_lang
		var spoken_line: Dictionary = source_line if lang == source_lang else target_lines[i]
		_set_speaker_focus(speaker)
		await _say_dialogue_line(spoken_line, lang, fallback_seconds)

func _say_dialogue_line(line: Dictionary, lang: String, fallback_seconds: float = 1.8) -> void:
	var text: String = str(line.get("text", ""))
	var voice: String = str(line.get("voice", "spirit"))
	if text.is_empty():
		return
	if feifei:
		feifei.show_hint(text, FeifeiShoulder.STATE_HINT, 0.0)
	voice_failure_intervention.add_turn("npc", text)
	var completed := await _synthesize_and_wait_for_tts(text, voice, lang)
	if not completed and fallback_seconds > 0.0:
		await get_tree().create_timer(fallback_seconds).timeout

func _synthesize_and_wait_for_tts(text: String, voice: String = "spirit", lang: String = "", timeout: float = TTS_PLAYBACK_TIMEOUT) -> bool:
	var audio_manager: Variant = _audio_manager()
	var hybrid_api: Variant = _hybrid_api()
	if not audio_manager or not hybrid_api:
		return false
	var tts_lang: String = lang if not lang.is_empty() else _source_language_code()
	var starting_playback_id: int = audio_manager.tts_playback_id
	var state_box := {
		"finished": false,
		"duration": 0.0
	}
	var tts_finished_cb := func(playback_id: int, duration: float):
		if playback_id > starting_playback_id:
			state_box["finished"] = true
			state_box["duration"] = duration
	audio_manager.tts_playback_finished.connect(tts_finished_cb)
	hybrid_api.synthesize_tts(text, voice, tts_lang)
	var elapsed := 0.0
	while not state_box["finished"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	if audio_manager.tts_playback_finished.is_connected(tts_finished_cb):
		audio_manager.tts_playback_finished.disconnect(tts_finished_cb)
	if state_box["finished"]:
		await get_tree().create_timer(maxf(TTS_MIC_BUFFER_MIN, float(state_box["duration"]) * 0.05)).timeout
	return bool(state_box["finished"])

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

	market_view = _build_market_view()
	inn_review_view = _build_inn_review_view()
	visual_root.add_child(market_view)
	visual_root.add_child(inn_review_view)
	inn_review_view.visible = false

	mist_overlay = ColorRect.new()
	mist_overlay.name = "ChaosMistOverlay"
	mist_overlay.color = Color(0.74, 0.78, 0.70, 0.30)
	mist_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_layer.add_child(mist_overlay)

	word_spirit_bar = HBoxContainer.new()
	word_spirit_bar.name = "WordSpiritBar"
	word_spirit_bar.position = Vector2(48, 928)
	word_spirit_bar.size = Vector2(1320, 104)
	word_spirit_bar.add_theme_constant_override("separation", 8)
	world_layer.add_child(word_spirit_bar)

func _build_market_view() -> Control:
	var root := _new_full_view("MarketMorningView", Color(0.50, 0.39, 0.28, 1.0))
	_add_band(root, "Sky", Color(0.86, 0.74, 0.55, 1.0), 0.0, 300.0)
	_add_band(root, "MarketGround", Color(0.33, 0.25, 0.20, 1.0), 760.0, 320.0)
	_add_label(root, "SceneTitle", "长安西市 · 西市晨钟", Vector2(88, 64), Vector2(760, 64), 34)
	_add_label(root, "Gate", "西市雾门", Vector2(790, 300), Vector2(340, 60), 28)
	_add_rect(root, "GateBody", Color(0.27, 0.14, 0.08, 1.0), Vector2(720, 360), Vector2(480, 360))
	_add_rect(root, "GateMist", Color(0.78, 0.76, 0.66, 0.42), Vector2(660, 330), Vector2(600, 430))
	step_title_label = _add_label(root, "StepTitle", "", Vector2(90, 160), Vector2(760, 52), 26)
	npc_status_label = _add_label(root, "NPCStatus", "", Vector2(90, 228), Vector2(760, 52), 24)
	_add_character_card(root, "天机阁执事", Vector2(250, 560), Color(0.18, 0.25, 0.26, 1.0))
	_add_character_card(root, "阿菱", Vector2(1260, 560), Color(0.32, 0.50, 0.35, 1.0))
	_add_character_card(root, "昊然", Vector2(1510, 590), Color(0.50, 0.36, 0.20, 1.0))
	return root

func _build_inn_review_view() -> Control:
	var root := _new_full_view("InnAfternoonReviewView", Color(0.31, 0.25, 0.21, 1.0))
	_add_band(root, "AfternoonSky", Color(0.77, 0.57, 0.42, 1.0), 0.0, 320.0)
	_add_label(root, "InnTitle", "蜃影客栈 · 下午复盘", Vector2(88, 64), Vector2(760, 64), 34)
	_add_rect(root, "LibraryPanel", Color(0.12, 0.11, 0.13, 0.82), Vector2(410, 260), Vector2(1100, 520))
	_add_label(root, "LibraryText", "词灵书阁", Vector2(760, 304), Vector2(420, 60), 32)
	return root

func _new_full_view(view_name: String, color: Color) -> Control:
	var root := Control.new()
	root.name = view_name
	root.size = VIEW_SIZE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_rect(root, "Background", color, Vector2.ZERO, VIEW_SIZE)
	return root

func _add_rect(parent: Control, node_name: String, color: Color, position: Vector2, size: Vector2) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.position = position
	rect.size = size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func _add_band(parent: Control, node_name: String, color: Color, top: float, height: float) -> ColorRect:
	return _add_rect(parent, node_name, color, Vector2(0, top), Vector2(VIEW_SIZE.x, height))

func _add_label(parent: Control, node_name: String, text: String, position: Vector2, size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = position
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _add_character_card(parent: Control, display_name: String, position: Vector2, color: Color) -> void:
	_add_rect(parent, "%sCard" % display_name, color, position, Vector2(180, 260))
	_add_label(parent, "%sName" % display_name, display_name, position + Vector2(0, 198), Vector2(180, 48), 24)

func _update_step_visuals() -> void:
	var step_id: String = str(current_step.get("id", ""))
	if market_view and inn_review_view:
		var is_review := step_id == "afternoon_review"
		market_view.visible = not is_review
		inn_review_view.visible = is_review
	if step_title_label:
		step_title_label.text = _step_title(step_id)
	if npc_status_label:
		npc_status_label.text = _step_status(step_id)

func _set_speaker_focus(speaker: String) -> void:
	if npc_status_label:
		npc_status_label.text = _speaker_label(speaker)

func _show_word_spirit(word: String) -> void:
	if not word_spirit_bar:
		return
	var chip := Label.new()
	chip.text = word
	chip.custom_minimum_size = Vector2(124, 54)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_font_size_override("font_size", 24)
	chip.add_theme_color_override("font_color", Color(1.0, 0.92, 0.56, 1.0))
	word_spirit_bar.add_child(chip)
	if feifei:
		feifei.show_hint("%s 词灵醒来了。" % word, FeifeiShoulder.STATE_HAPPY, 1.4)
	await get_tree().create_timer(0.35).timeout

func _animate_mist(delta: float) -> void:
	if not mist_overlay:
		return
	var pulse := sin(Time.get_ticks_msec() / 1000.0 * 0.75) * 0.05
	var target_alpha: float = 0.28 + pulse
	target_alpha -= minf(float(earned_words.size()) * 0.018, 0.15)
	mist_overlay.color.a = lerpf(mist_overlay.color.a, target_alpha, delta * 1.6)

func _setup_voice_failure_intervention() -> void:
	voice_failure_intervention = VoiceFailureInterventionScript.new()
	voice_failure_intervention.name = "VoiceFailureIntervention"
	add_child(voice_failure_intervention)
	voice_failure_intervention.set_feifei(feifei)
	voice_failure_intervention.set_failure_text_resolver(Callable(self, "_failure_turn_text"))
	voice_failure_intervention.set_tts_language_resolver(Callable(self, "_source_language_code"))
	voice_failure_intervention.configure({
		"scene_id": "chang_an_market_lesson_01",
		"npc_id": "feifei_west_market",
		"waiting_text": _loc("coach_waiting"),
		"fallback_text": _loc("coach_fallback"),
		"silence_ms": COACH_SILENCE_MS,
		"response_timeout": COACH_RESPONSE_TIMEOUT
	})
	voice_failure_intervention.start_session("chang-an-market-lesson-01")

func _failure_turn_text(reason: String) -> String:
	return "[%s] Player needs help with step %s." % [reason, str(current_step.get("id", "unknown"))]

func _set_quest_text(text: String) -> void:
	if quest_label:
		quest_label.text = text

func _loc(key: String) -> String:
	var is_zh := _source_language_code() == "zh"
	var strings := {
		"quest_good_morning": {"zh": "任务：对晨雾说 Good morning", "en": "Quest: Say Good morning"},
		"quest_name_register": {"zh": "任务：向天机阁执事登记名字", "en": "Quest: Register your name"},
		"quest_sit_here": {"zh": "任务：坐到发光石凳上", "en": "Quest: Sit on the bright stone"},
		"quest_meet_a_ling": {"zh": "任务：介绍阿菱的名字", "en": "Quest: Say A-Ling's name"},
		"quest_meet_haoran": {"zh": "任务：介绍昊然的名字", "en": "Quest: Say Haoran's name"},
		"quest_classmate_bond": {"zh": "任务：说出 new classmates", "en": "Quest: Say new classmates"},
		"quest_baize": {"zh": "任务：聆听白泽的认可", "en": "Quest: Listen to Baize"},
		"quest_afternoon_review": {"zh": "任务：下午回客栈复盘", "en": "Quest: Afternoon review"},
		"quest_review_a_ling": {"zh": "任务：向掌柜介绍阿灵", "en": "Quest: Introduce A-Ling to the innkeeper"},
		"quest_review_haoran": {"zh": "任务：向掌柜介绍浩然", "en": "Quest: Introduce Haoran to the innkeeper"},
		"quest_complete": {"zh": "完成：西市晨钟", "en": "Complete: West Market Morning Bell"},
		"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
		"coach_waiting": {"zh": "别着急，腓腓来帮你。", "en": "No rush. Feifei will help."},
		"coach_fallback": {"zh": "先说关键词也可以。跟着提示慢慢来。", "en": "Key words are enough. Follow the hint slowly."}
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""

func _step_title(step_id: String) -> String:
	var titles := {
		"good_morning": "晨光开门",
		"name_register": "雾门登记",
		"sit_here": "晨课石凳",
		"meet_a_ling": "认识阿菱",
		"meet_haoran": "认识昊然",
		"classmate_bond": "同修结伴",
		"baize_recognition": "白泽远观",
		"afternoon_review": "下午复盘",
		"review_a_ling": "记住阿菱",
		"review_haoran": "记住昊然"
	}
	return str(titles.get(step_id, "长安西市"))

func _step_status(step_id: String) -> String:
	var status := {
		"good_morning": "清晨的雾在西市门前翻动。",
		"name_register": "天机阁执事正在等待新来的声音。",
		"sit_here": "发光石凳正在等待你坐下。",
		"meet_a_ling": "阿菱的名字被雾扰乱了。",
		"meet_haoran": "昊然从香料摊旁冲出了迷雾。",
		"classmate_bond": "三位新同修站在晨课石凳前。",
		"baize_recognition": "远处的晨钟影子亮了一下。",
		"afternoon_review": "词灵书阁正在收拢今天的声音。",
		"review_a_ling": "阿菱的词灵头像亮了起来。",
		"review_haoran": "昊然的词灵头像亮了起来。"
	}
	return str(status.get(step_id, ""))

func _speaker_label(speaker: String) -> String:
	var labels := {
		"feifei": "腓腓正在引导你。",
		"tianji_steward": "天机阁执事正在确认规则。",
		"a_ling": "阿菱正在努力让名字稳定。",
		"haoran": "昊然正在辨认西市道路。",
		"baize_shadow": "白泽的影子在雾中回响。"
	}
	return str(labels.get(speaker, _step_status(str(current_step.get("id", "")))))

func _source_language_code() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.SOURCE_LANGUAGE_CODE)
	return "zh"

func _special_language_code() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.SPECIAL_LANGUAGE_CODE)
	return "en"

func _player_name() -> String:
	var manager: Variant = _game_manager()
	if manager and str(manager.player_name) != "":
		return str(manager.player_name)
	return "少侠"

func _player_level() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.player_cefr_level)
	return "A1"

func _game_manager() -> Variant:
	return get_node_or_null("/root/GameManager")

func _voice_pipeline() -> Variant:
	return get_node_or_null("/root/VoicePipeline")

func _hybrid_api() -> Variant:
	return get_node_or_null("/root/HybridAPI")

func _audio_manager() -> Variant:
	return get_node_or_null("/root/AudioManager")
