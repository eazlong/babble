## BeginningFP 序章第一人称场景控制器
##
## 对齐 PRD-v1.md §8：
# 序章：迷雾岛苏醒
# 场景
# 黑暗。
# 耳边传来风声。
# 浓雾翻滚。
# 玩家慢慢睁开眼睛。

##   feifei飞入, 并进行语音唤醒， 对话如下：
##   feifei: 你好啊，太好了，你醒了啊，外来人。我是腓腓。我发现你倒在了混沌迷雾里了，所以把你带到这里来。对了，你叫什么名字呀？
##   玩家: 说出自己的名字
##
## 如果说的是中文名字
##   feifei: 好的，好名字。不过迷雾岛周围的人们都说话很奇怪，使用了一种特殊的语言，叫英语，你需要有一个英语的名字。你可以告诉我你想要的英语名字吗？或者我帮你取一个（默认 Carl）。
##   玩家： 我叫 xx
##
##   feifei: {玩家名字}, 听起来很棒。我想你应该很好奇这是什么地方，这里叫做——迷雾岛，很久以前，这里和外面的世界连接在一起。可是不知道什么时候开始，这些混沌迷雾出现了，它覆盖了周围的大陆，也阻断了大家之间的交流。
##   
## 镜头展示远方被迷雾覆盖的大陆
##   feifei: 你看，远方的大陆都被迷雾覆盖了。在迷雾岛外面，还有六块大陆，传说中，保护这个世界的力量来自六件神器。可是不知道为什么，神器全部消失了…… 现在，守护迷雾岛的力量也越来越弱。
## 镜头转向远处破旧客栈
##   feifei  看到前面的客栈了吗？那里叫——蜃影客栈, 它就是这里没有迷雾的原因。它内部有一个阵法，阵法能量来源于六个神器，只是神器都遗失了。阵法也逐渐失去他的力量。我们去蜃影客栈看看吧，我带你去。
##   镜头跟随 Feifei 飞入客栈


extends Node2D

const Config = preload("res://assets/scripts/components/scene_config/spirit_forest_config.gd")

enum PrologueState {
	DREAM_WAKE,
	AWAIT_SOURCE_NAME,
	AWAIT_SPECIAL_NAME,
	WORLD_REVEAL,
	DISTANT_CONTINENTS,
	INN_REVEAL,
	ENTERING_INN,
	COMPLETED
}

const SCENE_ID: String = "beginning"
const FALLBACK_PLAYER_AGE: int = 8
const HELLO_HINT_DELAY: float = 5.0
const WAKE_FADE_DURATION: float = 2.6
const WAKE_FEIFEI_HEAD_START: float = 0.55

@onready var feifei: FeifeiShoulder = $FeifeiLayer/FeifeiShoulder
@onready var quest_tracker: Control = $HUDLayer/QuestTracker
@onready var mic_button: Control = $HUDLayer/MicButton
@onready var magic_compass: Control = $HUDLayer/MagicCompass
@onready var mid_layer: Node2D = $MidLayer
@onready var main_camera: Camera2D = $CameraSystem/MainCamera

var state: PrologueState = PrologueState.DREAM_WAKE
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
var last_player_input: String = ""
var player_source_name: String = ""
var player_display_name: String = ""
var completion_started: bool = false

var fog_overlay: ColorRect
var wake_vignette: ColorRect
var wake_top_lid: ColorRect
var wake_bottom_lid: ColorRect
var distant_continents: Node2D
var tea_shed: Node2D

signal prologue_completed()
signal task_completed(task_name: String)

func _ready() -> void:
	GameManager.current_scene = "BeginningFP"
	_create_prologue_visuals()
	_connect_runtime_signals()
	_set_quest_text(_loc("quest_wake"))
	_set_compass_label("…")
	if mic_button:
		mic_button.visible = false
	_start_prologue()

func _process(delta: float) -> void:
	_animate_mist(delta)

	if not voice_listening:
		return

	if VoicePipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
		if record_duration > Config.MAX_RECORD_DURATION:
			VoicePipeline.stop_listening()
			_stop_voice_listening()
	else:
		silence_timer += delta
		record_duration = 0.0
		if state in [PrologueState.AWAIT_SOURCE_NAME, PrologueState.AWAIT_SPECIAL_NAME] and silence_timer > HELLO_HINT_DELAY:
			silence_timer = 0.0
			if feifei:
				var hint_key := "special_name_retry" if state == PrologueState.AWAIT_SPECIAL_NAME else "name_retry"
				feifei.show_hint(_language_hint_text(hint_key), FeifeiShoulder.STATE_HINT, 0.0)

func _create_prologue_visuals() -> void:
	fog_overlay = ColorRect.new()
	fog_overlay.name = "ChaosMistOverlay"
	fog_overlay.color = Color(0.70, 0.78, 0.78, 0.34)
	fog_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$HUDLayer.add_child(fog_overlay)
	$HUDLayer.move_child(fog_overlay, 0)

	wake_vignette = ColorRect.new()
	wake_vignette.name = "WakeDarkness"
	wake_vignette.color = Color(0.0, 0.0, 0.0, 0.82)
	wake_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wake_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	$OverlayLayer.add_child(wake_vignette)

	wake_top_lid = _create_wake_lid("WakeTopLid", 0.0, 0.5)
	wake_bottom_lid = _create_wake_lid("WakeBottomLid", 0.5, 1.0)
	$OverlayLayer.add_child(wake_top_lid)
	$OverlayLayer.add_child(wake_bottom_lid)

	distant_continents = Node2D.new()
	distant_continents.name = "MistCoveredContinents"
	distant_continents.position = Vector2(960, 350)
	distant_continents.visible = false
	mid_layer.add_child(distant_continents)

	for i in range(6):
		var continent := Polygon2D.new()
		continent.name = "Continent%d" % (i + 1)
		var x := -540.0 + i * 215.0
		var y := 20.0 + sin(float(i)) * 28.0
		continent.polygon = PackedVector2Array([
			Vector2(x - 72.0, y + 34.0),
			Vector2(x - 32.0, y - 28.0),
			Vector2(x + 46.0, y - 40.0),
			Vector2(x + 86.0, y + 26.0),
			Vector2(x + 8.0, y + 54.0),
		])
		continent.color = Color(0.20, 0.27, 0.27, 0.58)
		distant_continents.add_child(continent)

	var continent_mist := ColorRect.new()
	continent_mist.name = "ContinentMistVeil"
	continent_mist.position = Vector2(-660, -78)
	continent_mist.size = Vector2(1320, 190)
	continent_mist.color = Color(0.74, 0.82, 0.82, 0.52)
	distant_continents.add_child(continent_mist)

	tea_shed = Node2D.new()
	tea_shed.name = "MirageInnRuins"
	tea_shed.position = Vector2(1180, 700)
	tea_shed.visible = false
	mid_layer.add_child(tea_shed)

	var shed_roof := Polygon2D.new()
	shed_roof.name = "Roof"
	shed_roof.polygon = PackedVector2Array([
		Vector2(-150, -50), Vector2(150, -50), Vector2(105, -115), Vector2(-105, -115)
	])
	shed_roof.color = Color(0.34, 0.16, 0.08, 0.96)
	tea_shed.add_child(shed_roof)

	var shed_body := ColorRect.new()
	shed_body.name = "TeaShedBody"
	shed_body.position = Vector2(-125, -50)
	shed_body.size = Vector2(250, 125)
	shed_body.color = Color(0.54, 0.36, 0.19, 0.92)
	tea_shed.add_child(shed_body)

	var inn_label := Label.new()
	inn_label.name = "InnLabel"
	inn_label.text = "蜃影客栈"
	inn_label.position = Vector2(-62, -22)
	inn_label.add_theme_font_size_override("font_size", 28)
	inn_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.62))
	tea_shed.add_child(inn_label)

func _connect_runtime_signals() -> void:
	if not HybridAPI.asr_received.is_connected(_on_asr_received):
		HybridAPI.asr_received.connect(_on_asr_received)
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

	var greeting := Config.get_dialogue("feifei_greeting", GameManager.SOURCE_LANGUAGE_CODE) % GameManager.SOURCE_LANGUAGE_NAME
	await _say_text(greeting, 0.0)
	state = PrologueState.AWAIT_SOURCE_NAME
	_set_quest_text(_loc("quest_source_name") % GameManager.SOURCE_LANGUAGE_NAME)
	_set_compass_label(GameManager.SOURCE_LANGUAGE_NAME)
	_start_voice_listening()

func _create_wake_lid(lid_name: String, top_anchor: float, bottom_anchor: float) -> ColorRect:
	var lid := ColorRect.new()
	lid.name = lid_name
	lid.color = Color.BLACK
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid.anchor_left = 0.0
	lid.anchor_top = top_anchor
	lid.anchor_right = 1.0
	lid.anchor_bottom = bottom_anchor
	return lid

func _play_wake_from_dream() -> void:
	if not wake_vignette or not wake_top_lid or not wake_bottom_lid:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wake_vignette, "color:a", 0.0, WAKE_FADE_DURATION * 0.85) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(wake_top_lid, "anchor_bottom", 0.03, WAKE_FADE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(wake_bottom_lid, "anchor_top", 0.97, WAKE_FADE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished
	wake_vignette.visible = false
	wake_top_lid.visible = false
	wake_bottom_lid.visible = false

func _animate_mist(delta: float) -> void:
	if not fog_overlay:
		return
	var pulse := sin(Time.get_ticks_msec() / 1000.0 * 0.8) * 0.04
	var target_alpha: float = 0.26 + pulse
	if state == PrologueState.DREAM_WAKE:
		target_alpha += 0.10
	elif state == PrologueState.COMPLETED:
		target_alpha = maxf(0.10, target_alpha - 0.16)
	fog_overlay.color.a = lerpf(fog_overlay.color.a, target_alpha, delta * 1.5)

func _on_player_response(text: String) -> void:
	last_player_input = text.strip_edges()
	if last_player_input.is_empty():
		await _repeat_current_prompt()
		return

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
	var ask_special_name := Config.get_dialogue("feifei_ask_special_name", GameManager.SOURCE_LANGUAGE_CODE) % [
		player_source_name,
		GameManager.SPECIAL_LANGUAGE_NAME,
		GameManager.SPECIAL_LANGUAGE_NAME,
		GameManager.SPECIAL_LANGUAGE_NAME,
	]
	await _say_text(ask_special_name, 0.0)
	state = PrologueState.AWAIT_SPECIAL_NAME
	_set_quest_text(_loc("quest_special_name") % GameManager.SPECIAL_LANGUAGE_NAME)
	_set_compass_label(GameManager.SPECIAL_LANGUAGE_NAME)
	_start_voice_listening()

func _handle_special_name(text: String) -> void:
	_stop_voice_listening()
	player_display_name = _extract_special_name(text)
	GameManager.set_player_info(player_display_name, FALLBACK_PLAYER_AGE)
	GameManager.lxp_score += Config.STAR_NAME_COLLECTION
	GameManager.save_progress()
	var scores := await HybridAPI.assess_player_input(text, "prologue_name", SCENE_ID)
	HybridAPI.report_quest_complete("prologue_name", SCENE_ID, scores, text)

	if feifei:
		feifei.play_happy()
	var celebrate := Config.get_dialogue("feifei_name_celebrate", GameManager.SOURCE_LANGUAGE_CODE) % player_display_name
	await _say_text(celebrate, 0.0)
	await _reveal_world()

func _reveal_world() -> void:
	state = PrologueState.WORLD_REVEAL
	_set_quest_text(_loc("quest_world"))
	_set_compass_label("!")
	await _speak("world_intro_mist_island", 5.5)
	state = PrologueState.DISTANT_CONTINENTS
	_set_quest_text(_loc("quest_continents"))
	_set_compass_label("迷雾")
	await _reveal_distant_continents()
	await _speak("world_intro_six_continents", 6.5)
	await _reveal_mirage_inn()

func _reveal_mirage_inn() -> void:
	state = PrologueState.INN_REVEAL
	_set_quest_text(_loc("quest_inn"))
	_set_compass_label("客栈")
	await _pan_to_mirage_inn()
	_reveal_tea_shed()
	await _speak("inn_intro", 7.0)
	state = PrologueState.ENTERING_INN
	_set_quest_text(_loc("quest_enter_inn"))
	_set_compass_label("进入")
	await _follow_feifei_into_inn()
	await _complete_prologue()

func _complete_prologue() -> void:
	if completion_started:
		return
	completion_started = true
	state = PrologueState.COMPLETED
	_set_quest_text(_loc("quest_complete"))
	_set_compass_label("长安")
	if feifei:
		feifei.play_happy()
	await _speak("inn_transition", 3.0)

	if not GameManager.unlocked_areas.has("BeginningFP"):
		GameManager.unlocked_areas.append("BeginningFP")
	if not GameManager.unlocked_areas.has("ChangAnMarket"):
		GameManager.unlocked_areas.append("ChangAnMarket")
	if not GameManager.completed_dialogues.has("beginning_prologue_complete"):
		GameManager.completed_dialogues.append("beginning_prologue_complete")
	GameManager.save_progress()
	prologue_completed.emit()

	await get_tree().create_timer(Config.SCENE_FADE_DURATION).timeout
	var change_result := get_tree().change_scene_to_file(Config.TARGET_SCENE_PATH)
	if change_result != OK:
		push_error("[BeginningFP] Failed to change to ChangAnMarket: %s" % error_string(change_result))

func _reveal_tea_shed() -> void:
	if not tea_shed:
		return
	tea_shed.visible = true
	tea_shed.modulate.a = 0.0
	tea_shed.scale = Vector2(0.92, 0.92)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(tea_shed, "modulate:a", 1.0, 1.0)
	tween.tween_property(tea_shed, "scale", Vector2.ONE, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

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

func _pan_to_mirage_inn() -> void:
	if not main_camera:
		return
	var tween := create_tween()
	tween.tween_property(main_camera, "position", Vector2(1180, 585), 1.3).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _follow_feifei_into_inn() -> void:
	if feifei and feifei.feifei_sprite:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(feifei.feifei_sprite, "position", Vector2(1180, 610), 1.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tween.tween_property(feifei.feifei_sprite, "scale", Vector2(0.45, 0.45), 1.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		await tween.finished
	await _speak("inn_follow_feifei", 2.0)

func _start_voice_listening() -> void:
	if voice_listening:
		return
	voice_listening = true
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = true
	VoicePipeline.start_listening()

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = false
	VoicePipeline.stop_listening()

func _continue_voice_listening() -> void:
	_stop_voice_listening()
	await get_tree().create_timer(0.15).timeout
	_start_voice_listening()

func _repeat_current_prompt() -> void:
	match state:
		PrologueState.AWAIT_SOURCE_NAME:
			if feifei:
				feifei.show_hint(_language_hint_text("name_retry"), FeifeiShoulder.STATE_HINT, 0.0)
		PrologueState.AWAIT_SPECIAL_NAME:
			if feifei:
				feifei.show_hint(_language_hint_text("special_name_retry"), FeifeiShoulder.STATE_HINT, 0.0)
		_:
			pass
	await _continue_voice_listening()

func _on_voice_started() -> void:
	print("[BeginningFP] Voice started")

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if not voice_listening:
		return
	_stop_voice_listening()
	if feifei:
		feifei.show_hint(_loc("recognizing"), FeifeiShoulder.STATE_HINT, 0.0)
	HybridAPI.recognize_speech(audio_data, _get_asr_language_for_state())

func _on_asr_received(result: Dictionary) -> void:
	if state not in [
		PrologueState.AWAIT_SOURCE_NAME,
		PrologueState.AWAIT_SPECIAL_NAME,
	]:
		return
	var text: String = result.get("text", "")
	await _on_player_response(text)

func _on_quest_status(_result: Dictionary) -> void:
	pass

func _on_quest_report(result: Dictionary) -> void:
	if result.get("success", false):
		var lxp: int = result.get("lxp_earned", 0)
		if lxp > 0:
			GameManager.lxp_score += lxp
			GameManager.save_progress()

func _speak(key: String, fallback_seconds: float = 2.0) -> void:
	await _say_text(Config.get_dialogue(key, GameManager.SOURCE_LANGUAGE_CODE), fallback_seconds)

func _say_text(text: String, fallback_seconds: float = 2.0) -> void:
	if text.is_empty():
		return
	if feifei:
		feifei.show_hint(text, FeifeiShoulder.STATE_HINT, 0.0)
	HybridAPI.synthesize_tts(text, "spirit", GameManager.SOURCE_LANGUAGE_CODE)
	if fallback_seconds > 0.0:
		await get_tree().create_timer(fallback_seconds).timeout
	else:
		await _await_tts()

func _await_tts(timeout: float = 8.0) -> bool:
	var state_box := {"done": false}
	var cb := func(_duration: float): state_box["done"] = true
	AudioManager.tts_finished.connect(cb)
	var elapsed := 0.0
	while not state_box["done"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	if AudioManager.tts_finished.is_connected(cb):
		AudioManager.tts_finished.disconnect(cb)
	return state_box["done"]

func _extract_name(text: String) -> String:
	var trimmed := text.strip_edges()
	var lower := trimmed.to_lower()
	for prefix in ["my name is ", "i am ", "i'm ", "我是", "我叫"]:
		if lower.begins_with(prefix):
			return trimmed.substr(prefix.length()).strip_edges()
	return trimmed

func _extract_special_name(text: String) -> String:
	if _contains_any(text, ["帮我取", "你取", "你帮", "帮我想", "随便", "都可以"]):
		return GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME
	var extracted := _extract_name(text)
	if extracted.is_empty():
		return GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME
	return extracted

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

func _language_hint_text(key: String) -> String:
	var language_name: String = GameManager.SPECIAL_LANGUAGE_NAME if key == "special_name_retry" else GameManager.SOURCE_LANGUAGE_NAME
	return _loc(key) % language_name

func _loc(key: String) -> String:
	var is_zh := GameManager.SOURCE_LANGUAGE_CODE == "zh"
	var strings := {
		"quest_wake": {"zh": "序章：从混沌迷雾中醒来", "en": "Prologue: Wake in the Chaos Mist"},
		"quest_source_name": {"zh": "任务：告诉腓腓你的%s名", "en": "Quest: Tell feifei your %s name"},
		"quest_special_name": {"zh": "任务：告诉腓腓你的%s名", "en": "Quest: Tell feifei your %s name"},
		"quest_world": {"zh": "任务：聆听迷雾岛的由来", "en": "Quest: Learn about Mist Island"},
		"quest_continents": {"zh": "任务：望向远方被迷雾覆盖的大陆", "en": "Quest: Look at the mist-covered continents"},
		"quest_inn": {"zh": "任务：看向蜃影客栈", "en": "Quest: Look toward Mirage Inn"},
		"quest_enter_inn": {"zh": "任务：跟随腓腓进入蜃影客栈", "en": "Quest: Follow feifei into Mirage Inn"},
		"quest_complete": {"zh": "序章完成：前往长安西市", "en": "Prologue complete: Go to Chang'an Market"},
		"name_retry": {"zh": "告诉腓腓你的%s名就可以。", "en": "Tell feifei your %s name."},
		"special_name_retry": {"zh": "告诉腓腓你的%s名，或者说“你帮我取一个”。", "en": "Tell feifei your %s name, or ask feifei to choose one."},
		"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
