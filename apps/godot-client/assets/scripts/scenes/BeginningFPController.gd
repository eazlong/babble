## BeginningFP 序章第一人称场景控制器（序章：蜃影初醒）
##
## 玩家在蜃影客栈主人房醒来；腓腓说明客栈已主动认主；
## 世界观由床前魔法投影揭示；不再有“看见客栈 / 走进客栈”演出。


extends Node2D

const Config = preload("res://assets/scripts/components/scene_config/beginning_config.gd")
const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")
const CoachContextTrackerScript = preload("res://assets/scripts/components/coach/CoachContextTracker.gd")
const VoiceFailureInterventionScript = preload("res://assets/scripts/components/voice/VoiceFailureIntervention.gd")
const DISTANT_CONTINENTS_TEXTURE: Texture2D = preload("res://assets/textures/backgrounds/beginning_mist_continents.png")
const WAKE_EYE_SHADER: Shader = preload("res://assets/resources/shaders/effects/wake_eye_open.gdshader")
const MIC_IDLE_TEXTURE: Texture2D = preload("res://assets/textures/ui/fp/ui_mic_button_idle.png")
const MIC_RECORDING_TEXTURE: Texture2D = preload("res://assets/textures/ui/fp/ui_mic_button_recording.png")

enum PrologueState {
	DREAM_WAKE,
	AWAIT_SOURCE_NAME,
	AWAIT_SPECIAL_NAME,
	WORLD_REVEAL,
	DISTANT_CONTINENTS,
	INN_EXPLANATION,
	COMPLETED
}

const SCENE_ID: String = "beginning"
const FALLBACK_PLAYER_AGE: int = 8
const HELLO_HINT_DELAY: float = 5.0
# 睁眼三段式：眼睑分开、暗角褪去露出双眼 -> 停顿一拍 -> 眼睛淡出露出世界
const EYE_REVEAL_DURATION: float = 1.4
const EYE_HOLD_DURATION: float = 0.7
const EYE_FADE_DURATION: float = 1.2
const WAKE_FEIFEI_HEAD_START: float = 0.55
const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
# ASR postprocess 可能花到 ASR_POSTPROCESS_TIMEOUT_MS(默认 30s) + Whisper 转写时间，
# 12s 会在接受提议(acceptance)等重推理场景超时，导致在途响应迟到后被 misroute。
# 对齐 postprocess 上限并留转写余量。
const ASR_TIMEOUT: float = 32.0
const COACH_SILENCE_MS: int = 15000
const COACH_RESPONSE_TIMEOUT: float = 8.0
const SLOT_AWAITING: String = "awaiting"
const SLOT_PROPOSED: String = "proposed"
const SLOT_FILLED: String = "filled"
const SPECIAL_NAME_POOL: Array[String] = [
	"Carl",
	"Wendy",
	"Leo",
	"Mia",
	"Luna",
]
# 提议态拒绝标记：英文整词匹配（避免 "Nolan" 命中 "no"）；
# 中文用完整短语（不用单字"不"，避免真人姓名误判）。
const DECLINE_MARKERS_EN: Array[String] = [
	"no", "nope", "not", "dont", "another", "different", "other", "else",
]
const DECLINE_MARKERS_ZH: Array[String] = [
	"不喜欢", "不好", "不要", "不行", "不想", "不对", "不是",
	"换一个", "换一个吧", "换个", "别的", "另一个", "另外", "再换",
]

@onready var feifei: FeifeiBody = $FeifeiLayer
@onready var quest_tracker: Control = $HUDLayer/QuestTracker
@onready var mic_button: Control = $MicLayer/MicButton
@onready var mic_button_icon: TextureRect = $MicLayer/MicButton/Button
@onready var magic_compass: Control = $HUDLayer/MagicCompass
@onready var mid_layer: Node2D = $InnLayer
@onready var main_camera: Camera2D = $CameraSystem/MainCamera

var state: PrologueState = PrologueState.DREAM_WAKE
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
var last_player_input: String = ""
var player_source_name: String = ""
var player_display_name: String = ""
var completion_started: bool = false
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
var coach_tracker: Variant = CoachContextTrackerScript.new()
var voice_failure_intervention: VoiceFailureIntervention
var asr_request_active: bool = false
var special_name_slot_state: String = SLOT_AWAITING
var proposed_special_name: String = ""
var recent_proposed_special_names: Array[String] = []

var wake_overlay: ColorRect
var distant_continents: Node2D

signal prologue_completed()
signal task_completed(task_name: String)

func _ready() -> void:
	# 环境音（批次 1 T16）：BeginningFP 无 BGM，只铺开始环境音床（两条启动路径都生效）
	if AudioManager:
		AudioManager.play_ambient_named("res://assets/audio/amb/beginning_ambient.ogg")
	if GameManager.should_resume_to_scene("BeginningFP"):
		# CLAUDE.md §11：不要在 _ready() 中直接抢切场景，
		# 否则会报 "Parent node is busy adding/removing children"。
		call_deferred("_resume_to_saved_scene")
		return

	GameManager.set_checkpoint("BeginningFP", not GameManager.is_test_mode_skip_auto_load_save())
	_load_dialogue_flows()
	_create_prologue_visuals()
	_setup_voice_failure_intervention()
	_connect_runtime_signals()
	_set_quest_text(_loc("quest_wake"))
	_set_compass_label("…")
	if mic_button:
		mic_button.visible = false
	_start_prologue()

## 延迟到节点树空闲后再切换场景（CLAUDE.md §11）。
func _resume_to_saved_scene() -> void:
	var resume_path: String = GameManager.get_scene_path()
	if resume_path.is_empty():
		push_error("[BeginningFP] Resume requested but saved scene path is empty.")
		return
	var resume_result := get_tree().change_scene_to_file(resume_path)
	if resume_result != OK:
		push_error("[BeginningFP] Failed to resume saved scene: %s" % error_string(resume_result))

func _exit_tree() -> void:
	if CoachClient:
		CoachClient.disconnect_socket()

func _process(delta: float) -> void:
	if not voice_listening:
		return

	if VoicePipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
	else:
		silence_timer += delta
		record_duration = 0.0
		if state in [PrologueState.AWAIT_SOURCE_NAME, PrologueState.AWAIT_SPECIAL_NAME] and silence_timer > HELLO_HINT_DELAY:
			silence_timer = 0.0
			await _handle_voice_attempt_failed("silence")

func _create_prologue_visuals() -> void:
	# 睁眼覆盖层：全屏纯黑遮罩，通过 shader 在中央开出一只宽圆角“眼睛”窗口；
	# 眼睛睁开时窗口垂直张开露出世界，随后整层淡出。
	_create_wake_overlay()

	distant_continents = Node2D.new()
	distant_continents.name = "MistCoveredContinents"
	distant_continents.position = Vector2(960, 350)
	distant_continents.visible = false
	mid_layer.add_child(distant_continents)

	var continent_sprite := Sprite2D.new()
	continent_sprite.name = "ContinentTexture"
	continent_sprite.texture = DISTANT_CONTINENTS_TEXTURE
	continent_sprite.centered = true
	distant_continents.add_child(continent_sprite)

func _connect_runtime_signals() -> void:
	if not HybridAPI.asr_received.is_connected(_on_asr_received):
		HybridAPI.asr_received.connect(_on_asr_received)
	if not HybridAPI.api_error.is_connected(_on_api_error):
		HybridAPI.api_error.connect(_on_api_error)
	if not HybridAPI.quest_status_received.is_connected(_on_quest_status):
		HybridAPI.quest_status_received.connect(_on_quest_status)
	if not HybridAPI.quest_report_received.is_connected(_on_quest_report):
		HybridAPI.quest_report_received.connect(_on_quest_report)
	if not VoicePipeline.voice_started.is_connected(_on_voice_started):
		VoicePipeline.voice_started.connect(_on_voice_started)
	if not VoicePipeline.voice_ended.is_connected(_on_voice_ended):
		VoicePipeline.voice_ended.connect(_on_voice_ended)

func _start_prologue() -> void:
	await get_tree().create_timer(0.5).timeout
	if feifei:
		feifei.visible = false
		feifei.play_entry_fly_in()

	await get_tree().create_timer(WAKE_FEIFEI_HEAD_START).timeout
	await _play_wake_from_dream()

	await _speak_flow("beginning.wake_greeting", 0.0)
	state = PrologueState.AWAIT_SOURCE_NAME
	_set_quest_text(_loc("quest_source_name") % GameManager.SOURCE_LANGUAGE_NAME)
	_set_compass_label(GameManager.SOURCE_LANGUAGE_NAME)
	_start_voice_listening()

func _create_wake_overlay() -> void:
	wake_overlay = ColorRect.new()
	wake_overlay.name = "WakeEyes"
	wake_overlay.color = Color.BLACK
	wake_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wake_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = WAKE_EYE_SHADER
	material.set_shader_parameter("eye_open", 0.0)
	material.set_shader_parameter("overlay_alpha", 1.0)
	wake_overlay.material = material
	$OverlayLayer.add_child(wake_overlay)

func _play_wake_from_dream() -> void:
	if not wake_overlay:
		return

	# 第一段：眼睛从细缝逐渐张开（眼睑中央分开，露出世界）。
	var material := wake_overlay.material as ShaderMaterial
	if material:
		material.set_shader_parameter("eye_open", 0.0)
		material.set_shader_parameter("overlay_alpha", 1.0)
		var reveal := create_tween()
		reveal.tween_method(
			func(value: float): material.set_shader_parameter("eye_open", value),
			0.0, 1.0, EYE_REVEAL_DURATION
		).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		await reveal.finished

		# 第二段：睁眼停顿一拍。
		await get_tree().create_timer(EYE_HOLD_DURATION).timeout
	else:
		# 降级兜底：shader 不可用时直接整层淡出，确保世界被揭露、不卡全黑。
		var guard := create_tween()
		guard.tween_property(wake_overlay, "modulate:a", 0.0, EYE_REVEAL_DURATION + EYE_HOLD_DURATION) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		await guard.finished
		wake_overlay.visible = false
		return

	# 第三段：眼睛全开后，整层遮罩淡出彻底露出世界。
	var fade := create_tween()
	fade.tween_method(
		func(value: float): material.set_shader_parameter("overlay_alpha", value),
		1.0, 0.0, EYE_FADE_DURATION
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await fade.finished
	wake_overlay.visible = false

func _on_player_response(text: String) -> void:
	last_player_input = text.strip_edges()
	if last_player_input.is_empty():
		await _handle_voice_attempt_failed("empty_asr")
		return
	voice_failure_intervention.reset_failures()
	voice_failure_intervention.add_turn("player", last_player_input)

	match state:
		PrologueState.AWAIT_SOURCE_NAME:
			await _handle_source_name(last_player_input)
		PrologueState.AWAIT_SPECIAL_NAME:
			await _handle_special_name(last_player_input)
		_:
			pass

func _handle_source_name(text: String) -> void:
	_stop_voice_listening()
	player_source_name = _extract_name(text)
	if player_source_name.is_empty():
		player_source_name = text.strip_edges()
	if feifei:
		feifei.play_happy()
		await feifei.settle_to_shoulder()

	if not _should_request_special_name(player_source_name):
		await _accept_display_name(player_source_name, text)
		return

	special_name_slot_state = SLOT_AWAITING
	proposed_special_name = ""
	recent_proposed_special_names.clear()
	await _speak_flow("beginning.ask_special_name", 0.0, {
		"player_source_name": player_source_name,
		"special_language_name": GameManager.SPECIAL_LANGUAGE_NAME,
	})
	state = PrologueState.AWAIT_SPECIAL_NAME
	_set_quest_text(_loc("quest_special_name") % GameManager.SPECIAL_LANGUAGE_NAME)
	_set_compass_label(GameManager.SPECIAL_LANGUAGE_NAME)
	_start_voice_listening()

func _handle_special_name(text: String) -> void:
	_stop_voice_listening()
	player_display_name = _extract_special_name(text)
	await _accept_display_name(player_display_name, text)

func _accept_display_name(display_name: String, assessment_text: String) -> void:
	player_display_name = display_name
	GameManager.set_player_info(player_display_name, FALLBACK_PLAYER_AGE)
	GameManager.lxp_score += Config.STAR_NAME_COLLECTION
	GameManager.save_progress()

	#var scores: Dictionary = await HybridAPI.assess_player_input(assessment_text, "prologue_name", SCENE_ID)
	#HybridAPI.report_quest_complete("prologue_name", SCENE_ID, scores, assessment_text)

	if feifei:
		feifei.play_happy()
	await _speak_flow("beginning.name_celebrate", 0.0, {
		"player_display_name": player_display_name,
	})
	await _reveal_world()

func _reveal_world() -> void:
	state = PrologueState.WORLD_REVEAL
	_set_quest_text(_loc("quest_world"))
	_set_compass_label("!")
	await _speak_flow("beginning.world_reveal_intro", 5.5)
	state = PrologueState.DISTANT_CONTINENTS
	_set_quest_text(_loc("quest_continents"))
	_set_compass_label("迷雾")
	await _reveal_distant_continents()
	await _speak_flow("beginning.distant_continents", 6.5)
	await _explain_inn()

## 第二幕收束：在主人房内说明玩家已在蜃影客栈中、阵法缺六神器。
func _explain_inn() -> void:
	state = PrologueState.INN_EXPLANATION
	_set_quest_text(_loc("quest_inn"))
	_set_compass_label("客栈")
	await _speak_flow("beginning.inn_reveal", 7.0)
	await _complete_prologue()

func _complete_prologue() -> void:
	if completion_started:
		return
	completion_started = true
	state = PrologueState.COMPLETED
	_set_quest_text(_loc("quest_complete"))
	_set_compass_label("客栈")
	if feifei:
		feifei.play_happy()
	# 已无“走进客栈”转场；留一小拍让最后一句 TTS 收尾。
	await get_tree().create_timer(0.8).timeout

	if not GameManager.unlocked_areas.has("BeginningFP"):
		GameManager.unlocked_areas.append("BeginningFP")
	if not GameManager.unlocked_areas.has("MirageInnIntroduction"):
		GameManager.unlocked_areas.append("MirageInnIntroduction")
	if not GameManager.completed_dialogues.has("beginning_prologue_complete"):
		GameManager.completed_dialogues.append("beginning_prologue_complete")
	GameManager.set_checkpoint("MirageInnIntroduction")
	prologue_completed.emit()

	await get_tree().create_timer(Config.SCENE_FADE_DURATION).timeout
	var change_result := get_tree().change_scene_to_file(Config.TARGET_SCENE_PATH)
	if change_result != OK:
		push_error("[BeginningFP] Failed to change to MirageInnIntroduction: %s" % error_string(change_result))

func _reveal_distant_continents() -> void:
	if not distant_continents:
		return
	distant_continents.visible = true
	distant_continents.modulate.a = 0.0
	distant_continents.position.y = 390.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(distant_continents, "modulate:a", 1.0, 1.2)
	tween.tween_property(distant_continents, "position:y", 350.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	if main_camera:
		tween.tween_property(main_camera, "position", Vector2(960, 430), 1.2).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _start_voice_listening() -> void:
	if voice_listening or asr_request_active:
		return
	voice_listening = true
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = true
	if mic_button_icon:
		mic_button_icon.texture = MIC_IDLE_TEXTURE
	VoicePipeline.start_listening()

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = false
	if mic_button_icon:
		mic_button_icon.texture = MIC_IDLE_TEXTURE
	VoicePipeline.stop_listening()

func _continue_voice_listening() -> void:
	_stop_voice_listening()
	await get_tree().create_timer(0.15).timeout
	_start_voice_listening()

func _repeat_current_prompt() -> void:
	match state:
		PrologueState.AWAIT_SOURCE_NAME, PrologueState.AWAIT_SPECIAL_NAME:
			if feifei:
				feifei.show_hint(_get_asr_retry_hint_for_state(), FeifeiShoulder.STATE_HINT, 0.0)
		_:
			pass
	await _continue_voice_listening()

func _on_voice_started() -> void:
	if mic_button_icon:
		mic_button_icon.texture = MIC_RECORDING_TEXTURE
	print("[BeginningFP] Voice started")

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if not voice_listening or asr_request_active:
		return
	_stop_voice_listening()
	if feifei:
		feifei.show_hint(_loc("recognizing"), FeifeiShoulder.STATE_HINT, 0.0)
	asr_request_active = true
	HybridAPI.recognize_speech(audio_data, _get_asr_language_for_state(), _build_asr_context_for_state())
	_watch_asr_timeout()

func _on_asr_received(result: Dictionary) -> void:
	if not asr_request_active:
		return
	asr_request_active = false
	if state not in [
		PrologueState.AWAIT_SOURCE_NAME,
		PrologueState.AWAIT_SPECIAL_NAME,
	]:
		return
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	if state == PrologueState.AWAIT_SPECIAL_NAME:
		await _handle_special_name_asr_result(result)
		return

	if not HybridAPI.get_asr_intent_matched(result, true):
		await _handle_asr_intent_not_matched(result)
		return
	var text: String = HybridAPI.get_asr_corrected_text(result).strip_edges()
	var extracted_name: String = HybridAPI.get_asr_extracted_value(result, "name", "").strip_edges()
	if not extracted_name.is_empty():
		text = extracted_name
	if text.is_empty():
		await _handle_voice_attempt_failed("empty_asr")
		return
	await _on_player_response(text)

func _handle_special_name_asr_result(result: Dictionary) -> void:
	var intent := HybridAPI.get_asr_intent(result)
	if intent == "delegate":
		# 首次 delegate 提议一个；PROPOSED 下再次 delegate 由 _propose_special_name()
		# 内部通过 recent_proposed_special_names 排除近期值，换一个新候选（CLAUDE.md §8）。
		await _propose_special_name()
		return

	var text: String = HybridAPI.get_asr_corrected_text(result).strip_edges()
	var extracted_name: String = HybridAPI.get_asr_extracted_value(result, "name", "").strip_edges()
	if not extracted_name.is_empty():
		# 提议态下 extracted 可能是玩家"接受提议"的回填，也可能是自己换的新名字。
		# 若回填值就是当前提议值，按接受处理，避免重复确认。
		if special_name_slot_state == SLOT_PROPOSED and extracted_name == proposed_special_name:
			await _accept_proposed_special_name()
			return
		special_name_slot_state = SLOT_FILLED
		await _handle_special_name(extracted_name)
		return

	if special_name_slot_state == SLOT_PROPOSED:
		# 提议态：provide 表示玩家对提议表态（voice-service 契约：
		# "Use provide when the player ... accepts/replaces a previous proposal"）。
		if _is_decline_utterance(text):
			await _decline_proposed_special_name()
			return
		if intent == "provide" and not text.is_empty():
			await _accept_proposed_special_name()
			return
		await _handle_proposal_not_understood(text)
		return

	if intent == "provide" and not text.is_empty():
		special_name_slot_state = SLOT_FILLED
		await _handle_special_name(text)
		return

	await _handle_asr_intent_not_matched(result)

## 提议态下的拒绝判定。
## voice-service 只产出 provide/delegate/off_topic（asr_postprocess.py IntentLabel），
## 没有 reject 标签，因此这里按玩家原话做客户端判定，避免"我说不好→她再问一次"的死循环。
## NOTE: 英文必须整词匹配——子串匹配会把 "Nolan"/"Nora" 这类名字误判成 "no"，
## 导致孩子报自己名字却被当成拒绝。中文短标记（换/别的）保留子串匹配，中文无词边界问题。
func _is_decline_utterance(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return false
	if _contains_any(normalized, DECLINE_MARKERS_ZH):
		return true
	return _contains_decline_word_en(normalized)

func _contains_decline_word_en(text: String) -> bool:
	var tokens := text.replace("'", " ").replace(",", " ").replace(".", " ").replace("!", " ").replace("?", " ").split(" ", false)
	for token in tokens:
		if DECLINE_MARKERS_EN.has(str(token)):
			return true
	return false

func _pick_special_name_candidate() -> String:
	for candidate in SPECIAL_NAME_POOL:
		if not recent_proposed_special_names.has(candidate):
			return candidate
	return GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME

func _propose_special_name() -> void:
	_stop_voice_listening()
	var candidate := _pick_special_name_candidate()
	proposed_special_name = candidate
	special_name_slot_state = SLOT_PROPOSED
	if not recent_proposed_special_names.has(candidate):
		recent_proposed_special_names.append(candidate)
	await _say_text(_loc("special_name_proposal") % candidate, 1.5, "spirit")
	_start_voice_listening()

## 玩家接受提议：落定并给一次明确的"改名"确认（beginning.accept_special_name）。
func _accept_proposed_special_name() -> void:
	_stop_voice_listening()
	var accepted := proposed_special_name
	if accepted.is_empty():
		accepted = GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME
	special_name_slot_state = SLOT_FILLED
	proposed_special_name = ""
	recent_proposed_special_names.clear()
	await _speak_flow("beginning.accept_special_name", 1.5, {
		"player_display_name": accepted,
	})
	await _handle_special_name(accepted)

## 玩家拒绝提议：不重复提议同一个，改为请玩家自己给名字
## （修复"我说不好 -> 她再问一次"的确认死循环）。
func _decline_proposed_special_name() -> void:
	_stop_voice_listening()
	special_name_slot_state = SLOT_AWAITING
	proposed_special_name = ""
	await _speak_flow("beginning.decline_special_name", 1.5, {
		"special_language_name": GameManager.SPECIAL_LANGUAGE_NAME,
	})
	_start_voice_listening()

## 提议态下没听懂：重念一次提议，不切换到别的候选，也不推进状态。
func _handle_proposal_not_understood(fallback_text: String) -> void:
	_stop_voice_listening()
	if fallback_text.is_empty() or fallback_text == proposed_special_name:
		fallback_text = _loc("special_name_proposal") % proposed_special_name
	await _say_text(fallback_text, 1.5, "spirit")
	_start_voice_listening()

func _handle_asr_intent_not_matched(result: Dictionary) -> void:
	var fallback: String = _get_asr_retry_hint_for_state()
	var npc_line := HybridAPI.get_asr_guidance_npc_line(result, fallback)
	if npc_line.is_empty():
		npc_line = fallback
	await _say_text(npc_line, 1.5, "spirit")
	await _continue_voice_listening()

func _on_api_error(_message: String) -> void:
	if not asr_request_active:
		return
	asr_request_active = false
	await _handle_voice_attempt_failed("api_error")

func _watch_asr_timeout() -> void:
	await get_tree().create_timer(ASR_TIMEOUT).timeout
	if not asr_request_active:
		return
	asr_request_active = false
	HybridAPI.cancel_in_flight_asr_request()
	push_warning("[BeginningFP] Voice service ASR timed out.")
	await _handle_voice_attempt_failed("asr_timeout")

func _handle_voice_attempt_failed(reason: String) -> void:
	if state not in [
		PrologueState.AWAIT_SOURCE_NAME,
		PrologueState.AWAIT_SPECIAL_NAME,
	]:
		return

	if voice_failure_intervention.register_failure(reason):
		await get_tree().create_timer(0.45).timeout
		_start_voice_listening()
		return

	await _repeat_current_prompt()

func _coach_failure_turn_text(reason: String) -> String:
	match reason:
		"silence":
			return "[no_voice_detected] Player did not speak during the prologue name prompt."
		"empty_asr":
			return "[empty_asr] Voice service returned no recognized text during the prologue name prompt."
		"api_error":
			return "[api_error] Voice service failed during the prologue name prompt."
		"asr_timeout":
			return "[asr_timeout] Voice service timed out during the prologue name prompt."
		"asr_error":
			return "[asr_error] Voice service returned an error during the prologue name prompt."
		_:
			return "[voice_retry] Player needs help during the prologue name prompt."

func _setup_voice_failure_intervention() -> void:
	voice_failure_intervention = VoiceFailureInterventionScript.new()
	voice_failure_intervention.name = "VoiceFailureIntervention"
	add_child(voice_failure_intervention)
	voice_failure_intervention.set_feifei(feifei)
	voice_failure_intervention.set_tracker(coach_tracker)
	voice_failure_intervention.set_failure_text_resolver(Callable(self, "_coach_failure_turn_text"))
	voice_failure_intervention.set_tts_language_resolver(Callable(self, "_get_asr_language_for_state"))
	voice_failure_intervention.configure({
		"scene_id": SCENE_ID,
		"npc_id": "feifei_beginning",
		"waiting_text": _loc("coach_waiting"),
		"fallback_text": _loc("coach_fallback"),
		"silence_ms": COACH_SILENCE_MS,
		"response_timeout": COACH_RESPONSE_TIMEOUT,
	})
	voice_failure_intervention.start_session("beginning")

func _on_quest_status(_result: Dictionary) -> void:
	pass

func _on_quest_report(result: Dictionary) -> void:
	if result.get("success", false):
		var lxp: int = result.get("lxp_earned", 0)
		if lxp > 0:
			GameManager.lxp_score += lxp
			GameManager.save_progress()

func _load_dialogue_flows() -> void:
	if not dialogue_flow_loader.load_dialogue_flows():
		push_warning("[BeginningFP] Dialogue flow config loaded with errors.")

func _speak_flow(flow_id: String, fallback_seconds: float = 2.0, params: Dictionary = {}) -> void:
	var lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, GameManager.SOURCE_LANGUAGE_CODE, params)
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
		# TTS 播报态：飞飞音（spirit）时身体 idle + 嘴部 talk_mouth 循环（其他 voice 不动嘴）
		if voice == "spirit":
			feifei.talk_speaking_start()
	voice_failure_intervention.add_turn("npc", text)
	var completed := await _synthesize_and_wait_for_tts(text, voice)
	if not completed:
		push_warning("[BeginningFP] TTS playback wait timed out; using fallback pacing.")
		if fallback_seconds > 0.0:
			await get_tree().create_timer(fallback_seconds).timeout
	if feifei and voice == "spirit":
		feifei.talk_speaking_end()

func _synthesize_and_wait_for_tts(text: String, voice: String = "spirit", timeout: float = TTS_PLAYBACK_TIMEOUT) -> bool:
	var starting_playback_id: int = AudioManager.tts_playback_id
	var state_box := {
		"received": false,
		"finished": false,
		"duration": 0.0,
	}
	var tts_received_cb := func(_result: Dictionary): state_box["received"] = true
	var tts_finished_cb := func(playback_id: int, duration: float):
		if playback_id > starting_playback_id:
			state_box["finished"] = true
			state_box["duration"] = duration

	HybridAPI.tts_received.connect(tts_received_cb)
	AudioManager.tts_playback_finished.connect(tts_finished_cb)
	HybridAPI.synthesize_tts(text, voice, GameManager.SOURCE_LANGUAGE_CODE)

	var elapsed := 0.0
	while not state_box["finished"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	if HybridAPI.tts_received.is_connected(tts_received_cb):
		HybridAPI.tts_received.disconnect(tts_received_cb)
	if AudioManager.tts_playback_finished.is_connected(tts_finished_cb):
		AudioManager.tts_playback_finished.disconnect(tts_finished_cb)

	if state_box["finished"]:
		var duration: float = state_box["duration"]
		await get_tree().create_timer(maxf(TTS_MIC_BUFFER_MIN, duration * 0.05)).timeout

	return state_box["finished"]

func _extract_name(text: String) -> String:
	var trimmed := text.strip_edges()
	var lower := trimmed.to_lower()
	for prefix in ["my name is ", "i am ", "i'm ", "我是", "我叫"]:
		if lower.begins_with(prefix):
			return trimmed.substr(prefix.length()).strip_edges()
	return trimmed

func _extract_special_name(text: String) -> String:
	var extracted := _extract_name(text)
	if extracted.is_empty():
		return GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME
	return extracted

func _should_request_special_name(name_text: String) -> bool:
	if GameManager.SOURCE_LANGUAGE_CODE == "zh" and GameManager.SPECIAL_LANGUAGE_CODE == "en":
		return not _is_english_name_candidate(name_text)
	return false

func _is_english_name_candidate(name_text: String) -> bool:
	var trimmed := name_text.strip_edges()
	if trimmed.is_empty() or _contains_cjk(trimmed):
		return false

	var has_letter := false
	for index in range(trimmed.length()):
		var codepoint := trimmed.unicode_at(index)
		if _is_ascii_letter(codepoint):
			has_letter = true
			continue
		if codepoint in [32, 39, 45, 46]:
			continue
		return false
	return has_letter

func _contains_cjk(text: String) -> bool:
	for index in range(text.length()):
		var codepoint := text.unicode_at(index)
		if (
			(codepoint >= 0x3400 and codepoint <= 0x4DBF)
			or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
			or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
		):
			return true
	return false

func _is_ascii_letter(codepoint: int) -> bool:
	return (
		(codepoint >= 65 and codepoint <= 90)
		or (codepoint >= 97 and codepoint <= 122)
	)

func _contains_any(text: String, needles: Array[String]) -> bool:
	var lower := text.to_lower()
	for needle in needles:
		if lower.contains(needle.to_lower()):
			return true
	return false

func _set_quest_text(text: String) -> void:
	if not quest_tracker:
		return
	var label: Label = quest_tracker.get_node_or_null("QuestLabel")
	if label:
		label.text = text

func _set_compass_label(text: String) -> void:
	if not magic_compass:
		return
	var label: Label = magic_compass.get_node_or_null("CompassLabel")
	if label:
		label.text = text

func _get_asr_language_for_state() -> String:
	if state == PrologueState.AWAIT_SPECIAL_NAME:
		return GameManager.SPECIAL_LANGUAGE_CODE
	return GameManager.SOURCE_LANGUAGE_CODE

func _build_asr_context_for_state() -> Dictionary:
	var expected_language_name := GameManager.SPECIAL_LANGUAGE_NAME if state == PrologueState.AWAIT_SPECIAL_NAME else GameManager.SOURCE_LANGUAGE_NAME
	var expected_slot := _build_special_name_slot(expected_language_name) if state == PrologueState.AWAIT_SPECIAL_NAME else {
		"key": "name",
		"type": "person_name",
		"description": "玩家告诉腓腓的%s名" % expected_language_name,
	}
	return {
		"session_id": voice_failure_intervention.get_session_id() if voice_failure_intervention else "",
		"user_id": GameManager.player_name if GameManager.player_name != "" else "anonymous",
		"npc_id": "feifei_beginning",
		"scene_id": SCENE_ID,
		"npc_question": _language_hint_text("special_name_retry") if state == PrologueState.AWAIT_SPECIAL_NAME else _language_hint_text("name_retry"),
		"expected_slots": [expected_slot],
		"expected_answer_type": "player_name",
		"target_intent": _get_asr_target_intent_for_state(),
		"intent_description": _get_asr_intent_description_for_state(),
		"candidate_answers": [],
		"recent_turns": voice_failure_intervention.get_recent_turns() if voice_failure_intervention else [],
		"player_level": GameManager.player_cefr_level,
		"language": _get_asr_language_for_state(),
	}

func _build_special_name_slot(expected_language_name: String) -> Dictionary:
	return {
		"key": "name",
		"type": "person_name",
		"description": "玩家告诉腓腓的%s名" % expected_language_name,
		"delegatable": true,
		"value_pool": SPECIAL_NAME_POOL,
		"pick_strategy": "exclude_recent",
		"proposal_template": _loc("special_name_proposal_template"),
		"slot_state": special_name_slot_state,
		"proposed_value": proposed_special_name,
	}

func _get_asr_retry_hint_for_state() -> String:
	if state == PrologueState.AWAIT_SPECIAL_NAME:
		return _language_hint_text("special_name_retry")
	return _language_hint_text("name_retry")

func _get_asr_target_intent_for_state() -> String:
	if state == PrologueState.AWAIT_SPECIAL_NAME:
		return "provide_special_language_name_or_request_default"
	return "provide_source_name"

func _get_asr_intent_description_for_state() -> String:
	if state == PrologueState.AWAIT_SPECIAL_NAME:
		return "The player should tell Feifei their special-language name, or explicitly ask Feifei to choose one for them. If neither happens, intent_matched must be false and guidance.npc_line should guide them to say a special-language name or ask Feifei to choose."
	return "The player should tell Feifei their source-language name. If the player does not provide a name, intent_matched must be false and guidance.npc_line should ask them to say their name."

func _language_hint_text(key: String) -> String:
	var language_name: String = GameManager.SPECIAL_LANGUAGE_NAME if key == "special_name_retry" else GameManager.SOURCE_LANGUAGE_NAME
	return _loc(key) % language_name

func _loc(key: String) -> String:
	var is_zh := GameManager.SOURCE_LANGUAGE_CODE == "zh"
	var strings := {
		"quest_wake": {"zh": "序章：在蜃影客栈醒来", "en": "Prologue: Wake in Mirage Inn"},
		"quest_source_name": {"zh": "任务：告诉腓腓你的%s名", "en": "Quest: Tell feifei your %s name"},
		"quest_special_name": {"zh": "任务：告诉腓腓你的%s名", "en": "Quest: Tell feifei your %s name"},
		"quest_world": {"zh": "任务：聆听迷雾岛的由来", "en": "Quest: Learn about Mist Island"},
		"quest_continents": {"zh": "任务：看腓腓投影中的六道光", "en": "Quest: Watch the six lights in Feifei's vision"},
		"quest_inn": {"zh": "任务：了解蜃影客栈与阵法", "en": "Quest: Learn about Mirage Inn and its formation"},
		"quest_complete": {"zh": "序章完成：蜃影初醒", "en": "Prologue complete: First Awakening at Mirage Inn"},
		"name_retry": {"zh": "告诉腓腓你的%s名就可以。", "en": "Tell feifei your %s name."},
		"special_name_retry": {"zh": "告诉腓腓你的%s名，或者说“你帮我取一个”。", "en": "Tell feifei your %s name, or ask feifei to choose one."},
		"special_name_proposal": {"zh": "那就叫%s，你觉得怎么样？", "en": "How about %s? Do you like it?"},
		"special_name_proposal_template": {"zh": "那就叫{value}，你觉得怎么样？", "en": "How about {value}? Do you like it?"},
		"special_name_decline_hint": {"zh": "不喜欢的话就说“换一个”，或者直接告诉我你想要的名字。", "en": "If you don't like it, say 'another one', or just tell me the name you want."},
		"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
		"coach_waiting": {"zh": "别着急，腓腓来帮你。", "en": "No rush. Feifei will help."},
		"coach_fallback": {"zh": "我们慢慢来。你可以靠近一点，对着麦克风说出你的名字。", "en": "Let's take it slowly. Move a little closer and say your name into the microphone."},
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
