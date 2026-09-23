## 长安西市第一课：西市晨钟，初入长安
##
## Implements the P1 gameplay spec for Grade 4 Unit 1 "Meeting new people":
## voice greeting, name registration, sit interaction, her/his name contrast,
## classmate bond, Baize recognition, and afternoon review.
extends Node2D

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")
const LessonResponseMatcherScript = preload("res://assets/scripts/core/lesson_response_matcher.gd")
const VoiceFailureInterventionScript = preload("res://assets/scripts/components/voice/VoiceFailureIntervention.gd")

const DEFAULT_CONFIG_PATH: String = "res://assets/resources/scene_configs/chang_an_market_lesson_01.json"
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

@onready var feifei: FeifeiBody = get_node_or_null("FeifeiLayer")
@onready var mic_button: Control = get_node_or_null("MicLayer/MicButton")
@onready var quest_label: Label = get_node_or_null("HUDLayer/QuestTracker/QuestLabel")

## 每课一份场景配置；复制场景文件时只需改这个路径即可复用本控制器。
@export var config_path: String = DEFAULT_CONFIG_PATH

var state: LessonState = LessonState.LOADING
var config: Dictionary = {}
var steps: Array = []
var current_step_index: int = -1
# 东华钟八响：每响之间的停顿（秒）。
var bell_strike_interval: float = 0.65
var current_step: Dictionary = {}
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
var voice_failure_intervention: VoiceFailureIntervention
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
var asr_request_active: bool = false
var earned_words: Array[String] = []

## 测试缝：headless 测试没有音频后端，TTS 播放完成信号永远不会到达；
## 置 true 时跳过 TTS 播放等待，让集成测试能走完整条链路。
## 仅由测试设置，运行时默认 false。见 test/scenes/test_chang_an_market_lesson_01.gd。
var test_skip_narration_wait: bool = false

## 测试缝：集成测试直接驱动整课到 COMPLETED，不能让完成时真的切场景；置 true 跳过推进。
var test_skip_scene_transition: bool = false

var world_layer: CanvasLayer
var visual_root: Control
var market_view: Control
var inn_review_view: Control
var mist_overlay: TextureRect
var step_title_label: Label
var npc_status_label: Label
var word_spirit_bar: HBoxContainer
var fade_overlay: ColorRect

func _ready() -> void:
	_load_config()
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint(str(config.get("checkpoint_id", "ChangAnMarket")), not manager.is_test_mode_skip_auto_load_save())
	# BGM + 环境音（批次 1 T16）：长安集市——轻快不喧宾夺主 + 集市人声床
	var audio: Variant = _audio_manager()
	if audio:
		audio.play_bgm_named("res://assets/audio/bgm/changan_market_bgm.ogg")
		audio.play_ambient_named("res://assets/audio/amb/changan_market_ambient.ogg")
	_load_dialogue_flows()
	_build_visuals()
	_setup_voice_failure_intervention()
	_connect_runtime_signals()

	# ASR test 模式：本课的"玩家该说的话"从 scene_config 的 test_asr_audio_names 取
	# （按步骤顺序，一条对应一轮语音作答）。脚本 scripts/record_player_answers.py 生成音频，
	# scripts/sync_player_answers_to_configs.py 把清单写回 config，两边不会漂移。
	# 之前这里硬编码成 ["my_name_is_carl.wav"]，第一轮之后每轮都听到同一句 →
	# 卡在 name_register 反复重问，整课走不下去。
	_configure_test_asr_audio()
	if mic_button:
		mic_button.visible = false
	_start_lesson()

func _configure_test_asr_audio() -> void:
	var names: Array[String] = []
	for value in config.get("test_asr_audio_names", []):
		var trimmed := str(value).strip_edges()
		if not trimmed.is_empty():
			names.append(trimmed)
	if names.is_empty():
		return
	HybridAPI.set_asr_default_answer_test_enabled(
		true,
		str(config.get("test_asr_audio_dir", "res://assets/test_audio/")),
		names
	)
	# 每课从自己的第一条答案开始，不受上一个场景轮换位置影响。
	HybridAPI.reset_asr_test_audio_index()

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
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("[ChangAnMarket] Failed to load config: %s" % config_path)
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
	var quest_key: String = str(current_step.get("quest_key", ""))
	var step_text: String = _step_text(str(current_step.get("id", "")), "quest_text")
	_set_quest_text(step_text if not step_text.is_empty() else _loc(quest_key))
	await _speak_flow(str(current_step.get("flow_id", "")), 1.8)
	# 东华钟八响（T35）：雾门开启（gate_open）时敲响长安钟。
	if str(current_step.get("id", "")) == "gate_01.gate_open":
		await play_donghuang_bell(8)

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
	_set_quest_text(_completion_text())
	var manager: Variant = _game_manager()
	if manager:
		var completion_id: String = str(config.get("completion_dialogue_id", "chang_an_market_lesson_01_complete"))
		if not manager.completed_dialogues.has(completion_id):
			manager.completed_dialogues.append(completion_id)
		var next_unlock: String = str(config.get("next_unlock", ""))
		if not next_unlock.is_empty() and not manager.unlocked_areas.has(next_unlock):
			manager.unlocked_areas.append(next_unlock)
		manager.lxp_score += int(config.get("lxp_reward", 0))
		manager.complete_mainline_episode(next_unlock)
		manager.save_progress()
	if feifei:
		feifei.play_happy()
	await _advance_to_next_lesson()

func _fade_to_black() -> void:
	if not fade_overlay:
		return
	var tween := create_tween()
	tween.tween_property(fade_overlay, "color:a", 1.0, 0.65).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

## 章节推进：先把下一课记进 GameManager，再回蜃影客栈 hub 复盘与出发。
## hub 未注册或处于测试缝时只保留记账，停在完成态。
func _advance_to_next_lesson() -> void:
	var next_id: String = str(config.get("next_unlock", ""))
	var manager: Variant = _game_manager()
	if manager and not next_id.is_empty():
		manager.set_next_lesson(next_id)
	if test_skip_scene_transition:
		return
	var hub_path: String = GameManager.get_scene_path("MirageInnHub")
	if hub_path.is_empty():
		print("[ChangAnMarket] 蜃影客栈 hub 未注册，停在完成状态。")
		return
	if manager:
		manager.set_checkpoint("MirageInnHub")
	await _fade_to_black()
	var change_result := get_tree().change_scene_to_file(hub_path)
	if change_result != OK:
		push_error("[ChangAnMarket] Failed to change to MirageInnHub: %s" % error_string(change_result))

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
		feifei.show_hint(_loc("recognizing"), FeifeiBody.STATE_HINT, 0.0)
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

## 步骤里声明为"报名字"的锚点短语；命中它时把玩家自己的名字加进候选，
## 见 _effective_candidate_phrases 的说明。
const NAME_STEP_ANCHORS: Array[String] = ["my name is", "i am", "name"]

func _build_asr_context() -> Dictionary:
	var expected: Dictionary = current_step.get("asr", {})
	var phrases: Array = _effective_candidate_phrases(expected)
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

## 候选短语 = 步骤声明的 clear/acceptable + （报名字步骤）玩家自己的名字。
##
## 为什么需要补名字：voice-service 的取值层对 provide 会把**自由槽的表面形式**收紧，
## 实测同一句「My name is Leo.」在同一个步骤上下文里会给出两种 extracted
## （`"My name is Leo."` 或 `"Leo"`）。后者经 `_asr_text()`（优先 extracted）
## 送进 LessonResponseMatcher 后既不含 clear_phrase「my name is」也不含关键词「name」
## → 判 needs_help，孩子会被无限重问。把名字本身加进候选，两条取值路径都能过。
func _effective_candidate_phrases(expected: Dictionary) -> Array:
	var phrases: Array = expected.get("clear_phrases", []) + expected.get("acceptable_phrases", [])
	if not _is_name_step(expected):
		return phrases
	var player_name: String = _player_name().strip_edges()
	if not player_name.is_empty() and player_name != "anonymous" and not phrases.has(player_name):
		phrases.append(player_name)
	return phrases

func _is_name_step(expected: Dictionary) -> bool:
	var declared: Array = expected.get("clear_phrases", []) + expected.get("acceptable_phrases", [])
	for phrase in declared:
		if NAME_STEP_ANCHORS.has(str(phrase).to_lower()):
			return true
	return false

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
			_set_npc_emotion(str(line.get("speaker", "")), str(line.get("emotion", "")))
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
		_set_npc_emotion(speaker, str(source_line.get("emotion", "")))
		await _say_dialogue_line(spoken_line, lang, fallback_seconds)

func _say_dialogue_line(line: Dictionary, lang: String, fallback_seconds: float = 1.8) -> void:
	var text: String = str(line.get("text", ""))
	var voice: String = str(line.get("voice", "spirit"))
	if text.is_empty():
		return
	if feifei:
		feifei.show_hint(text, FeifeiBody.STATE_HINT, 0.0)
		# TTS 播报态：飞飞音（spirit）时身体 idle + 嘴部 talk_mouth 循环（其他 voice 不动嘴）
		if voice == "spirit":
			feifei.talk_speaking_start()
	voice_failure_intervention.add_turn("npc", text)
	var completed := await _synthesize_and_wait_for_tts(text, voice, lang)
	if not completed and fallback_seconds > 0.0:
		await get_tree().create_timer(fallback_seconds).timeout
	if feifei and voice == "spirit":
		feifei.talk_speaking_end()

func _synthesize_and_wait_for_tts(text: String, voice: String = "spirit", lang: String = "", timeout: float = TTS_PLAYBACK_TIMEOUT) -> bool:
	if test_skip_narration_wait:
		# 视为"已播完"，调用方因此跳过 fallback 计时，测试得以快速推进。
		return true
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
	# T6 修正：场景美术建在 CanvasLayer 里，layer=0 时 Godot 会把它绘制在**默认画布之上**，
	# 从而盖住世界空间的 FeifeiBody（迁移后腓腓是世界空间节点，不再像旧的 FeifeiShoulder 那样
	# 自己在 CanvasLayer(20) 里）。取 -50：仍在 ParallaxBackground(-100) 之上，但在默认画布(0)
	# 与所有 UI(HUD 10 / dialogue 20 / overlay 30 / mic 90) 之下，层级恢复正常。
	world_layer.layer = -50
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

	# 混沌雾（批次 2 T36）：真实雾纹理 + 0.30 alpha，_animate_mist 仍做脉动。
	mist_overlay = TextureRect.new()
	mist_overlay.name = "ChaosMistOverlay"
	var mist_tex: Texture2D = load("res://assets/textures/backgrounds/changan_mist_overlay.png") as Texture2D
	if mist_tex != null:
		mist_overlay.texture = mist_tex
		mist_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mist_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	else:
		push_warning("[ChangAnMarket] 雾纹理缺失，雾层退化为透明")
	mist_overlay.modulate = Color(0.74, 0.78, 0.70, 0.30)
	mist_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_layer.add_child(mist_overlay)

	word_spirit_bar = HBoxContainer.new()
	word_spirit_bar.name = "WordSpiritBar"
	word_spirit_bar.position = Vector2(48, 928)
	word_spirit_bar.size = Vector2(1320, 104)
	word_spirit_bar.add_theme_constant_override("separation", 8)
	world_layer.add_child(word_spirit_bar)

	fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color(0.04, 0.04, 0.05, 0.0)
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var overlay_layer: CanvasLayer = get_node_or_null("OverlayLayer")
	if overlay_layer:
		overlay_layer.add_child(fade_overlay)

func _build_market_view() -> Control:
	var root := _new_full_view("MarketMorningView", Color(0.50, 0.39, 0.28, 1.0))
	_background_texture(root, "res://assets/textures/backgrounds/changan_stall_street_bg.png")
	_add_band(root, "Sky", Color(0.86, 0.74, 0.55, 0.0), 0.0, 300.0)
	_add_band(root, "MarketGround", Color(0.33, 0.25, 0.20, 0.0), 760.0, 320.0)
	_add_label(root, "SceneTitle", "长安西市 · 西市晨钟", Vector2(88, 64), Vector2(760, 64), 34)
	_add_label(root, "Gate", "西市雾门", Vector2(790, 300), Vector2(340, 60), 28)
	_add_rect(root, "GateBody", Color(0.27, 0.14, 0.08, 0.30), Vector2(720, 360), Vector2(480, 360))
	_add_rect(root, "GateMist", Color(0.78, 0.76, 0.66, 0.42), Vector2(660, 330), Vector2(600, 430))
	step_title_label = _add_label(root, "StepTitle", "", Vector2(90, 160), Vector2(760, 52), 26)
	npc_status_label = _add_label(root, "NPCStatus", "", Vector2(90, 228), Vector2(760, 52), 24)
	_add_npc_sprite(root, "天机阁执事Sprite", "天机阁执事", Vector2(250, 560))
	_add_npc_sprite(root, "阿菱Sprite", "阿菱", Vector2(1260, 560))
	_add_npc_sprite(root, "昊然Sprite", "昊然", Vector2(1510, 590))
	return root

func _build_inn_review_view() -> Control:
	var root := _new_full_view("InnAfternoonReviewView", Color(0.31, 0.25, 0.21, 1.0))
	_background_texture(root, "res://assets/textures/backgrounds/changan_inn_review_bg.png")
	_add_band(root, "AfternoonSky", Color(0.77, 0.57, 0.42, 0.0), 0.0, 320.0)
	_add_label(root, "InnTitle", "蜃影客栈 · 下午复盘", Vector2(88, 64), Vector2(760, 64), 34)
	_add_rect(root, "LibraryPanel", Color(0.12, 0.11, 0.13, 0.55), Vector2(410, 260), Vector2(1100, 520))
	_add_label(root, "LibraryText", "词灵书阁", Vector2(760, 304), Vector2(420, 60), 32)
	_add_npc_sprite(root, "白泽Sprite", "白泽", Vector2(560, 230))
	return root

func _new_full_view(view_name: String, color: Color) -> Control:
	var root := Control.new()
	root.name = view_name
	root.size = VIEW_SIZE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background_texture(root, "")  # 先占位；调用方随后用真实路径覆盖。
	_add_rect(root, "Background", color, Vector2.ZERO, VIEW_SIZE)
	return root

# 背景真实纹理（批次 2 T36）：加载 1920×1080 背景图；失败则保留 ColorRect 回退并告警。
# background_path 为空时不加载（用于回退占位）。
func _background_texture(root: Control, background_path: String) -> void:
	if background_path.is_empty():
		return
	var bg_path: String = background_path
	var tex: Texture2D = load(bg_path) as Texture2D
	if tex == null:
		push_warning("[ChangAnMarket] 背景纹理缺失，回退 ColorRect: %s" % bg_path)
		return
	# 移除占位的纯色 Background，换成真实纹理。
	var old: Node = root.get_node_or_null("Background")
	if old:
		root.remove_child(old)
		old.queue_free()
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# 背景必须是视图最底层：移到第一个子节点。
	root.move_child(bg, 0)

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

# NPC 精灵（批次 2 T36）：AnimatedSprite2D 加载 8 帧 SpriteFrames，底对齐到 position，播 idle。
# display_name 用于名称 Label；node_name 是带 Sprite 后缀的唯一节点名。
func _add_npc_sprite(parent: Control, node_name: String, display_name: String, position: Vector2) -> void:
	var frames_path := "res://assets/sprites/%s/%s_sprite_frames.tres" % [_npc_dir(display_name), _npc_dir(display_name)]
	var frames: SpriteFrames = load(frames_path) as SpriteFrames
	if frames == null:
		push_warning("[ChangAnMarket] NPC SpriteFrames 缺失，回退彩色卡片: %s" % frames_path)
		_add_character_card(parent, display_name, position, Color(0.35, 0.3, 0.25, 1.0))
		return
	var spr := AnimatedSprite2D.new()
	spr.name = node_name
	spr.sprite_frames = frames
	spr.position = position
	spr.scale = Vector2(0.9, 0.9)
	parent.add_child(spr)
	if frames.has_animation("idle"):
		spr.play("idle")
	_add_label(parent, "%sName" % display_name, display_name, position + Vector2(0, 268), Vector2(180, 40), 22)

# 显示名 → 资源目录（天机阁执事 映射到 tianji_clerk）。
func _npc_dir(display_name: String) -> String:
	match display_name:
		"天机阁执事": return "tianji_clerk"
		"阿菱": return "aling"
		"昊然": return "haoran"
		"白泽": return "baize"
		"胡商": return "hu_merchant"
	return display_name

func _update_step_visuals() -> void:
	var step_id: String = str(current_step.get("id", ""))
	if market_view and inn_review_view:
		var use_inn_review: bool = str(current_step.get("view", "market")) == "inn_review"
		market_view.visible = not use_inn_review
		inn_review_view.visible = use_inn_review
	if step_title_label:
		step_title_label.text = _step_title(step_id)
	if npc_status_label:
		npc_status_label.text = _step_status(step_id)

func _set_speaker_focus(speaker: String) -> void:
	if npc_status_label:
		npc_status_label.text = _speaker_label(speaker)

# 情绪驱动 NPC 帧（批次 2 T37）：emotion → 动画名，映射到 market_view 里对应的 AnimatedSprite2D。
# 未映射的 speaker（feifei / baize_shadow 不在市场视图）直接忽略，回到 idle 由调用方处理。
const NPC_SPEAKER_NODE := {
	"tianji_steward": "天机阁执事Sprite",
	"a_ling": "阿菱Sprite",
	"haoran": "昊然Sprite"
}

func _set_npc_emotion(speaker: String, emotion: String) -> void:
	var node_name: String = NPC_SPEAKER_NODE.get(speaker, "")
	if node_name.is_empty() or market_view == null:
		return
	var spr: Node = market_view.get_node_or_null(node_name)
	if not (spr is AnimatedSprite2D):
		return
	var anim: String = "idle"
	match emotion:
		"talking": anim = "talk"
		"happy": anim = "happy"
		_: anim = "idle"
	var frames: SpriteFrames = (spr as AnimatedSprite2D).sprite_frames
	if frames != null and frames.has_animation(anim):
		if (spr as AnimatedSprite2D).animation != anim:
			(spr as AnimatedSprite2D).play(anim)

# 东华钟八响（批次 2 T35）：依次敲响 n 声长安钟，间隔 bell_strike_interval。
# 复用批次 1 的 changan_bell_ring 音效；n<=0 时不响。
func play_donghuang_bell(n: int = 8) -> void:
	if n <= 0:
		return
	for i in range(n):
		var audio: Variant = _audio_manager()
		if audio:
			audio.play_sfx("changan_bell_ring")
		if i < n - 1:
			await get_tree().create_timer(bell_strike_interval).timeout

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
		feifei.show_hint("%s 词灵醒来了。" % word, FeifeiBody.STATE_HAPPY, 1.4)
	await get_tree().create_timer(0.35).timeout

func _animate_mist(delta: float) -> void:
	if not mist_overlay:
		return
	var pulse := sin(Time.get_ticks_msec() / 1000.0 * 0.75) * 0.05
	var target_alpha: float = 0.28 + pulse
	target_alpha -= minf(float(earned_words.size()) * 0.018, 0.15)
	mist_overlay.modulate.a = lerpf(mist_overlay.modulate.a, target_alpha, delta * 1.6)

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
	voice_failure_intervention.start_session(str(config.get("scene_id", "chang-an-market-lesson-01")))

func _failure_turn_text(reason: String) -> String:
	return "[%s] Player needs help with step %s." % [reason, str(current_step.get("id", "unknown"))]

func _set_quest_text(text: String) -> void:
	if quest_label:
		quest_label.text = text

func _loc(key: String) -> String:
	var is_zh := _source_language_code() == "zh"
	var strings := {
		"quest_complete": {"zh": "完成：雾门问居", "en": "Complete: The Mist Gate"},
		"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
		"coach_waiting": {"zh": "别着急，腓腓来帮你。", "en": "No rush. Feifei will help."},
		"coach_fallback": {"zh": "先说关键词也可以。跟着提示慢慢来。", "en": "Key words are enough. Follow the hint slowly."}
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""

func _step_text(step_id: String, field: String) -> String:
	for step in steps:
		if str(step.get("id", "")) == step_id:
			var value: Variant = step.get(field, "")
			if value is Dictionary:
				var is_zh: bool = _source_language_code() == "zh"
				return str(value.get("zh" if is_zh else "en", ""))
			return str(value)
	return ""

func _completion_text() -> String:
	var value: Variant = config.get("completion_text", {})
	if value is Dictionary:
		var is_zh: bool = _source_language_code() == "zh"
		var text: String = str(value.get("zh" if is_zh else "en", ""))
		if not text.is_empty():
			return text
	return _loc("quest_complete")

func _step_title(step_id: String) -> String:
	var from_config: String = _step_text(step_id, "title")
	if not from_config.is_empty():
		return from_config
	var titles := {}
	return str(titles.get(step_id, "长安西市"))

func _step_status(step_id: String) -> String:
	var from_config: String = _step_text(step_id, "status")
	if not from_config.is_empty():
		return from_config
	var status := {}
	return str(status.get(step_id, ""))

func _speaker_label(speaker: String) -> String:
	var labels := {
		"feifei": "腓腓正在引导你。",
		"tianji_steward": "天机阁执事正在确认规则。",
		"a_ling": "阿菱正在努力让名字稳定。",
		"haoran": "昊然正在辨认西市道路。",
		"baize_shadow": "白泽的影子在雾中回响。",
		"nest_keeper": "守巢人正在照看坊墙上的灵兽。"
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
