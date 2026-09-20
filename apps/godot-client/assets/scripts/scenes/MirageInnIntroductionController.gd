## 蜃影客栈首次导览场景（第三幕：大本营导览）
##
## 语音推进的导览场景：从主人房接续醒来，先认识自己的房间与词灵书阁，
## 再经过大厅、阵法房间、客房预告，最后总结。不再包含“走进客栈”演出。
extends Node2D

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")
const VoiceFailureInterventionScript = preload("res://assets/scripts/components/voice/VoiceFailureIntervention.gd")

enum InnIntroState {
	OWNER_ROOM,
	AWAIT_SCROLL_CALL,
	WORD_SPIRIT_LIBRARY,
	WARDROBE_PREVIEW,
	HALL,
	FORMATION_ROOM,
	GUEST_ROOM_PREVIEW,
	SUMMARY,
	## hub 复访入口：腓腓把两条路都摆出来，玩家自己选——继续主线，还是去词灵阁玩。
	HUB_AWAIT_CHOICE,
	## 玩家选了出发但阵法能量不足：只认词灵阁口令，先把门控讲清楚（ADR 0003 §4/§10）。
	HUB_AWAIT_CHARGE,
	COMPLETED
}

const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
const MAX_RECORD_DURATION: float = 8.0
const SILENCE_HINT_DELAY: float = 5.0
const COACH_SILENCE_MS: int = 15000
const COACH_RESPONSE_TIMEOUT: float = 8.0
const TARGET_SCENE_PATH: String = "res://assets/scenes/MirageInnHub.tscn"
const VIEW_SIZE: Vector2 = Vector2(1920, 1080)
## hub 语音出发口令。与启动主人房「继续旅程」共用 StoryContinueMarkers，避免 ASR 候选白名单两处漂移。
const StoryContinueMarkersScript = preload("res://assets/scripts/core/story_continue_markers.gd")
const LIBRARY_ENTRY_MARKERS: Array[String] = [
	"\u8bcd\u7075\u9601",
	"\u4e66\u9601",
	"\u8bcd\u7075\u4e66\u9601",
	"\u5145\u80fd",
	"library",
	"archive",
	"word spirit",
]

## hub 回客栈时的二选一提示（ADR 0003 §15：词灵阁始终可进）。
## - 通用：两条路都能走（能量满，或有在途情节可免费续行）；
## - 充能：能量不足，先讲门控再听词灵阁口令；
## - 加练：没有可玩下一情节，主线走不了，但词灵阁照样开着。
const HUB_CHOICE_FLOW: String = "inn_introduction.hub_choice_prompt"
const HUB_CHOICE_CHARGE_FLOW: String = "inn_introduction.hub_choice_charge_prompt"
const HUB_CHOICE_PRACTICE_FLOW: String = "inn_introduction.hub_choice_practice_prompt"

const HALL_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_hall_bg.png")
const FORMATION_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_formation_room_bg.png")
const OWNER_ROOM_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_owner_room_bg.png")
const WORD_SPIRIT_LIBRARY_BACKGROUND = preload("res://assets/textures/backgrounds/word_spirit_library_bg.png")
const GUEST_ROOM_BACKGROUND = preload("res://assets/textures/backgrounds/mirage_inn_guest_room_bg.png")
const ARTIFACT_SEAT_EMPTY = preload("res://assets/textures/objects/inn/artifact_seat_empty.png")
const ARTIFACT_FIRST_LIGHT = preload("res://assets/textures/objects/inn/artifact_first_light.png")
## 书阁入口已从书柜改为墙上画卷（口令「画中小世界」）。
const SCROLL_DORMANT = preload("res://assets/textures/objects/inn/scroll_dormant.png")
const SCROLL_AWAKE = preload("res://assets/textures/objects/inn/scroll_awake.png")
const WARDROBE_EMPTY = preload("res://assets/textures/objects/inn/wardrobe_empty.png")
const WORD_SPIRIT_HELLO = preload("res://assets/textures/objects/inn/word_spirit_hello.png")
const GUEST_ROOM_DISTANT_LIGHT = preload("res://assets/textures/objects/inn/guest_room_distant_light.png")

## 第 1 学期（东皇钟）八响进度：每完成一课记一响。
const LESSON_COMPLETION_IDS: Array[String] = [
	"changan_gate_01_complete",
	"changan_eaves_02_complete",
]

## hub 模式：跳过序章剧情，直接进入复盘与出发的客栈大厅。
@export var hub_mode: bool = false

@onready var feifei: FeifeiBody = $FeifeiLayer
@onready var mic_button: Control = $MicLayer/MicButton
@onready var quest_label: Label = $HUDLayer/QuestTracker/QuestLabel

var state: InnIntroState = InnIntroState.OWNER_ROOM
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
var voice_failure_intervention: VoiceFailureIntervention
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0

var world_layer: CanvasLayer
var visual_root: Control
var hall_view: Control
var formation_view: Control
var owner_room_view: Control
var library_view: Control
var guest_view: Control
var fade_overlay: ColorRect
var first_light: TextureRect
var scroll_dormant_prop: TextureRect
var scroll_awake_prop: TextureRect
var wardrobe_empty: TextureRect
var formation_pips: Array[TextureRect] = []
var formation_projection: TextureRect

## ASR test 模式：本场景（导览 / hub 两种模式）各自需要哪句"玩家台词"。
## 必须由场景自己声明，不能靠 project.godot 的全局轮换——玩家从存档直接续到本场景时，
## 全局轮换还停在开头，会把序章的名字答案当成"唤醒画卷"喂进来（实测：前两轮 off_topic、
## 孩子被反复重问，看起来就是"说画中小世界一直不成功"）。
const TEST_ASR_AUDIO_DIR: String = "res://assets/test_audio/"
const TEST_ASR_INTRO_ANSWERS: Array[String] = ["pa_03_intro_scroll_call.wav"]
const TEST_ASR_HUB_ANSWERS: Array[String] = ["pa_04_hub_depart.wav"]

func _ready() -> void:
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint("MirageInnHub" if hub_mode else "MirageInnIntroduction")
	_load_dialogue_flows()
	_build_visuals()
	_update_formation_energy_visuals()
	_setup_voice_failure_intervention()
	_connect_runtime_signals()
	_configure_test_asr_audio()
	if mic_button:
		mic_button.visible = false
	if hub_mode:
		_start_hub()
	else:
		_start_intro()
	# BGM + 环境音（批次 1 T16）：幻影客栈——客栈环境音 + 归档厅 BGM 低音量暂用
	var audio: Variant = _audio_manager()
	if audio:
		audio.play_bgm_named("res://assets/audio/bgm/archive_hall_bgm.ogg")
		audio.set_bgm_volume(0.3)
		audio.play_ambient_named("res://assets/audio/amb/inn_ambient.ogg")

## test-audio 模式下给本场景装一套自己的答案（导览=唤醒画卷；hub=出发），
## 并把轮换位置归零，这样无论从哪个场景进来都对得上。
func _configure_test_asr_audio() -> void:
	if not HybridAPI.asr_default_answer_test_enabled:
		return
	var answers: Array[String] = TEST_ASR_HUB_ANSWERS if hub_mode else TEST_ASR_INTRO_ANSWERS
	HybridAPI.set_asr_default_answer_test_enabled(true, TEST_ASR_AUDIO_DIR, answers)
	HybridAPI.reset_asr_test_audio_index()

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

	state = InnIntroState.OWNER_ROOM
	_set_quest_text(_loc("quest_owner_room"))
	await _show_view(owner_room_view)
	await _speak_flow("inn_introduction.owner_room", 2.0)

	state = InnIntroState.AWAIT_SCROLL_CALL
	_set_quest_text(_loc("quest_scroll"))
	await _speak_flow("inn_introduction.scroll_voice_prompt", 2.0)
	_start_voice_listening()

## 客栈 hub（复访）：阵法房间复盘 + 二选一（继续主线 / 去词灵阁玩）。
## 无论存档处于哪种状态，入口都先给选择，不再按状态单向派活：
## 能量满只提出发、能量不足只提充能、没有下一情节干脆不监听——那三种写法都让
## "我想去词灵阁玩"没有出口（ADR 0003 §15 要求词灵阁始终可进）。
func _start_hub() -> void:
	await _show_view(formation_view)
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint("MirageInnHub")
	_update_formation_energy_visuals()
	if feifei:
		feifei.visible = true
		feifei.show_hint(_hub_words_hint(), FeifeiBody.STATE_HINT, 0.0)
	await _enter_hub_choice()

## 进入二选一：说“出发 / Let's go”继续主线，说“词灵阁 / 书阁 / 充能”去归卷厅复习。
func _enter_hub_choice() -> void:
	state = InnIntroState.HUB_AWAIT_CHOICE
	_set_quest_text(_formation_energy_status_text() + "\n" + _hub_choice_quest_line())
	await _speak_flow(_hub_choice_flow_id(), 2.5, {"missing": _formation_energy_missing_text()})
	_start_voice_listening()

## 按存档状态挑提示词（纯函数，便于单测）：
## 没有可走的路 → 加练提示；要充能且不能免费续行 → 充能提示；其余 → 通用二选一。
static func hub_choice_flow_for(has_resumable_trip: bool, has_next_lesson: bool, needs_charge: bool) -> String:
	if not has_resumable_trip and not has_next_lesson:
		return HUB_CHOICE_PRACTICE_FLOW
	if needs_charge and not has_resumable_trip:
		return HUB_CHOICE_CHARGE_FLOW
	return HUB_CHOICE_FLOW

func _hub_choice_flow_id() -> String:
	var manager: Variant = _game_manager()
	var needs_charge: bool = false
	if manager:
		needs_charge = bool(manager.should_recharge_before_departure())
	return hub_choice_flow_for(_has_resumable_trip(), not _next_lesson_path().is_empty(), needs_charge)

## 在途情节（"已付费"）且目标场景可玩 → 可以免费续行，不看阵法能量。
func _has_resumable_trip() -> bool:
	var manager: Variant = _game_manager()
	if not manager or not manager.has_active_formation_trip():
		return false
	return manager.has_playable_lesson(str(manager.get_formation_active_episode()))

## 此刻有没有可走的主线路：续行，或存在可玩的下一情节。
func _hub_departure_available() -> bool:
	return _has_resumable_trip() or not _next_lesson_path().is_empty()

## 现在说「出发」能否立刻成行：续行免费，否则必须满格（ADR 0003 §4/§10）。
func _hub_departure_ready() -> bool:
	if _has_resumable_trip():
		return true
	var manager: Variant = _game_manager()
	if not manager:
		return false
	return bool(manager.is_formation_full())

func _formation_energy_missing_text() -> String:
	var manager: Variant = _game_manager()
	if not manager:
		return "0"
	return str(maxi(0, int(manager.get_formation_energy_max()) - int(manager.get_formation_energy())))

func _hub_choice_quest_line() -> String:
	if _hub_departure_available():
		return _loc("quest_hub_choice")
	return _loc("quest_hub_choice_practice")

## ASR context 的 npc_question：拿正在问的那句提示当上下文，别写死一句。
func _hub_choice_question_text() -> String:
	return _localized_flow_text(_hub_choice_flow_id())

func _hub_summary_text() -> String:
	return "蜃影客栈 · %s" % _bell_progress_text()

func _hub_words_hint() -> String:
	var manager: Variant = _game_manager()
	var words: Array = manager.vocabulary_learned if manager else []
	if words.is_empty():
		return "欢迎回到蜃影客栈。今天还没有学到新词。"
	var recent: Array = words.slice(maxi(words.size() - 8, 0), words.size())
	var parts: PackedStringArray = []
	for word in recent:
		parts.append(str(word))
	return "欢迎回到蜃影客栈。今天学过的词：%s" % "  ".join(parts)

func _bell_progress_text() -> String:
	var manager: Variant = _game_manager()
	var done: int = 0
	if manager:
		for completion_id in LESSON_COMPLETION_IDS:
			if manager.completed_dialogues.has(completion_id):
				done += 1
	return "东皇钟 · 第 %d 响 / 8" % done

func _next_lesson_path() -> String:
	var manager: Variant = _game_manager()
	if not manager:
		return ""
	return GameManager.get_scene_path(str(manager.get_next_lesson()))

func _depart_for_next_lesson() -> void:
	var manager: Variant = _game_manager()
	# 在途情节凭"已付费"免费续行，不看阵法能量（ADR 0003 §4/§10）。
	if _has_resumable_trip():
		var active_path: String = GameManager.get_scene_path(str(manager.get_formation_active_episode()))
		_stop_voice_listening()
		await _fade_to_black()
		var active_result := get_tree().change_scene_to_file(active_path)
		if active_result != OK:
			push_error("[MirageInnHub] Failed to resume active episode: %s" % error_string(active_result))
		return
	var next_path: String = _next_lesson_path()
	if next_path.is_empty():
		# 没有再可玩的主线情节：不能装作能出发。回到二选一，词灵阁照样开着（ADR 0003 §15）。
		await _enter_hub_choice()
		return
	if manager:
		if not manager.is_formation_full():
			state = InnIntroState.HUB_AWAIT_CHARGE
			_set_quest_text(_formation_energy_status_text() + "\n" + _localized_flow_text("inn_introduction.hub_charge_retry"))
			await _speak_flow("inn_introduction.hub_charge_retry", 2.0)
			_start_voice_listening()
			return
		var next_id: String = str(manager.get_next_lesson())
		if not manager.start_formation_trip(next_id):
			state = InnIntroState.HUB_AWAIT_CHARGE
			_set_quest_text(_formation_energy_status_text() + "\n" + _localized_flow_text("inn_introduction.hub_charge_retry"))
			await _speak_flow("inn_introduction.hub_charge_retry", 2.0)
			_start_voice_listening()
			return
	_stop_voice_listening()
	await _fade_to_black()
	var change_result := get_tree().change_scene_to_file(next_path)
	if change_result != OK:
		push_error("[MirageInnHub] Failed to change scene: %s" % error_string(change_result))

func _continue_after_scroll_call() -> void:
	_stop_voice_listening()
	if feifei:
		feifei.play_happy()
	await _speak_flow("inn_introduction.scroll_opened", 1.5)

	state = InnIntroState.WORD_SPIRIT_LIBRARY
	_set_quest_text(_loc("quest_library"))
	await _show_view(library_view)
	await _speak_flow("inn_introduction.word_spirit_library", 2.0, {
		"word_text": "hello",
	})

	state = InnIntroState.WARDROBE_PREVIEW
	_set_quest_text(_loc("quest_wardrobe"))
	await _show_view(owner_room_view)
	await _focus_wardrobe()
	await _speak_flow("inn_introduction.wardrobe_preview", 2.0)

	state = InnIntroState.HALL
	_set_quest_text(_loc("quest_hall"))
	await _show_view(hall_view)
	await _speak_flow("inn_introduction.hall", 2.0)

	state = InnIntroState.FORMATION_ROOM
	_set_quest_text(_loc("quest_formation"))
	await _show_view(formation_view)
	await _speak_flow("inn_introduction.formation_room", 2.0)

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
		manager.set_next_lesson("ChangAnMarket")
		manager.set_checkpoint("MirageInnHub")

	await _fade_to_black()
	var change_result := get_tree().change_scene_to_file(TARGET_SCENE_PATH)
	if change_result != OK:
		push_error("[MirageInnIntroduction] Failed to change to MirageInnHub: %s" % error_string(change_result))

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

	hall_view = _build_hall_view()
	formation_view = _build_formation_view()
	owner_room_view = _build_owner_room_view()
	library_view = _build_library_view()
	guest_view = _build_guest_view()

	for view in [hall_view, formation_view, owner_room_view, library_view, guest_view]:
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
	formation_pips.clear()
	var root := _new_full_view("FormationRoomView", FORMATION_BACKGROUND)
	var center := Vector2(960, 570)
	for i in range(6):
		var angle := TAU * float(i) / 6.0 - PI / 2.0
		var pos := center + Vector2(cos(angle), sin(angle)) * 255.0
		_add_texture(root, "ArtifactSeat%d" % (i + 1), ARTIFACT_SEAT_EMPTY, pos - Vector2(64, 64), Vector2(128, 128))

	first_light = _add_texture(root, "FirstArtifactLight", ARTIFACT_FIRST_LIGHT, center - Vector2(48, 48), Vector2(96, 96))
	for i in range(8):
		var pip_angle := TAU * float(i) / 8.0 - PI / 2.0
		var pip_pos := center + Vector2(cos(pip_angle), sin(pip_angle)) * 175.0
		var pip := _add_texture(root, "FormationEnergyPip%d" % (i + 1), ARTIFACT_FIRST_LIGHT, pip_pos - Vector2(18, 18), Vector2(36, 36))
		formation_pips.append(pip)
		pip.modulate = Color(0.22, 0.20, 0.28, 0.55)
	formation_projection = _add_texture(root, "SpiritProjection", WORD_SPIRIT_HELLO, center - Vector2(120, 120), Vector2(240, 240))
	formation_projection.modulate = Color(0.75, 0.82, 1.0, 0.45)
	formation_projection.visible = false
	return root

func _build_owner_room_view() -> Control:
	var root := _new_full_view("OwnerRoomView", OWNER_ROOM_BACKGROUND)
	# 书阁入口已从书柜改为墙上画卷（口令「画中小世界」）。
	# 画卷贴在背景画卷的画心位置（背景画心实测 x908-1092, y288-624），
	# 贴图 198x351 四周留 6px 余量盖住旧画心，避免残留原先那张画。
	scroll_dormant_prop = _add_texture(root, "ScrollDormant", SCROLL_DORMANT, Vector2(902, 282), Vector2(198, 351))
	scroll_awake_prop = _add_texture(root, "ScrollAwake", SCROLL_AWAKE, Vector2(902, 282), Vector2(198, 351))
	scroll_awake_prop.visible = false
	# 书柜已随入口改画卷一并删除（用户 2026-09-20：删除书柜美术资源），房间里不再有书柜。
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

func _set_scroll_awake(is_awake: bool) -> void:
	if scroll_dormant_prop:
		scroll_dormant_prop.visible = not is_awake
	if scroll_awake_prop:
		scroll_awake_prop.visible = is_awake

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
		feifei.show_hint(text, FeifeiBody.STATE_HINT, 0.0)
		# TTS 播报态：飞飞音（spirit）时身体 idle + 嘴部 talk_mouth 循环（其他 voice 不动嘴）
		if voice == "spirit":
			feifei.talk_speaking_start()
	voice_failure_intervention.add_turn("npc", text)
	var completed := await _synthesize_and_wait_for_tts(text, voice)
	if not completed and fallback_seconds > 0.0:
		push_warning("[MirageInnIntroduction] TTS playback wait timed out; using fallback pacing.")
		await get_tree().create_timer(fallback_seconds).timeout
	if feifei and voice == "spirit":
		feifei.talk_speaking_end()

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
	if state == InnIntroState.AWAIT_SCROLL_CALL:
		_set_scroll_awake(true)
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
		feifei.show_hint(_loc("recognizing"), FeifeiBody.STATE_HINT, 0.0)
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		var asr_context: Dictionary
		match state:
			InnIntroState.HUB_AWAIT_CHOICE:
				asr_context = _build_hub_choice_asr_context()
			InnIntroState.HUB_AWAIT_CHARGE:
				asr_context = _build_library_entry_asr_context()
			_:
				asr_context = _build_scroll_asr_context()
		hybrid_api.recognize_speech(audio_data, _source_language_code(), asr_context)

func _on_asr_received(result: Dictionary) -> void:
	if state == InnIntroState.HUB_AWAIT_CHOICE:
		await _handle_hub_choice_asr(result)
		return
	if state == InnIntroState.HUB_AWAIT_CHARGE:
		await _handle_hub_charge_asr(result)
		return
	if state != InnIntroState.AWAIT_SCROLL_CALL:
		return
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	var text := _asr_answer_text(result)
	if _is_scroll_call(text):
		voice_failure_intervention.reset_failures()
		voice_failure_intervention.add_turn("player", text)
		await _continue_after_scroll_call()
		return

	await _handle_voice_attempt_failed("wrong_answer")

## hub 二选一的语音裁决：出发意图走主线段（含能量门控），词灵阁意图进归卷厅。
func _handle_hub_choice_asr(result: Dictionary) -> void:
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	var text := _asr_answer_text(result)
	if _is_depart_call(text):
		voice_failure_intervention.reset_failures()
		voice_failure_intervention.add_turn("player", text)
		_stop_voice_listening()
		# 能量不足时不先道贺：由 _depart_for_next_lesson 讲明"要先充能"并改听词灵阁口令。
		if _hub_departure_ready():
			await _speak_flow("inn_introduction.hub_depart_ack", 2.0)
		await _depart_for_next_lesson()
		return
	if await _try_enter_library_from_text(text):
		return
	await _handle_voice_attempt_failed("wrong_answer")

func _handle_voice_attempt_failed(reason: String) -> void:
	if state not in [InnIntroState.AWAIT_SCROLL_CALL, InnIntroState.HUB_AWAIT_CHOICE, InnIntroState.HUB_AWAIT_CHARGE]:
		return
	if voice_failure_intervention.register_failure(reason):
		await get_tree().create_timer(0.45).timeout
		_start_voice_listening()
		return

	var retry_text: String = _loc("scroll_retry")
	if state == InnIntroState.HUB_AWAIT_CHOICE:
		retry_text = _loc("hub_choice_retry")
	elif state == InnIntroState.HUB_AWAIT_CHARGE:
		retry_text = _localized_flow_text("inn_introduction.hub_charge_retry")
	if feifei:
		feifei.show_hint(retry_text, FeifeiBody.STATE_HINT, 0.0)
	await get_tree().create_timer(0.35).timeout
	_start_voice_listening()

func _is_scroll_call(text: String) -> bool:
	# 唤醒词同样要先归一繁体：Whisper 对普通话口令经常输出繁体（实测「书架」→「書架」，
	# 现在这句口令会输出成「畫中小世界」），而 candidate_answers 只有简体
	# （见 StoryContinueMarkers.TRADITIONAL_VARIANTS，畫→画 就为此存在）。
	var lower := StoryContinueMarkersScript.normalize_variants(text).to_lower()
	return lower.contains("画中小世界") or lower.contains("little world") or lower.contains("painting")

func _is_depart_call(text: String) -> bool:
	return StoryContinueMarkersScript.matches(text)

func _set_quest_text(text: String) -> void:
	if quest_label:
		quest_label.text = text

## 场景内文案表（zh = 母语，en = 目标语言）。做成类常量 + 静态取用，方便单测直接
## 断言"提示里有没有把那两句口令都教出来"（hub 二选一最怕提示漏教一句）。
const LOC_STRINGS: Dictionary = {
	"quest_owner_room": {"zh": "任务：认识自己的房间", "en": "Quest: Learn about your room"},
	"quest_formation": {"zh": "任务：查看阵法房间", "en": "Quest: Inspect the formation room"},
	"quest_hall": {"zh": "任务：认识客栈大厅", "en": "Quest: Learn about the hall"},
	"quest_scroll": {"zh": "任务：说“画中小世界”", "en": "Quest: Say \"the little world in the painting\""},
	"quest_library": {"zh": "任务：进入词灵书阁", "en": "Quest: Enter the Word Spirit Library"},
	"quest_wardrobe": {"zh": "任务：查看衣橱", "en": "Quest: Preview the wardrobe"},
	"quest_guest_room": {"zh": "任务：查看客房", "en": "Quest: Preview the guest room"},
	"quest_summary": {"zh": "任务：记住客栈的三个房间", "en": "Quest: Remember the three rooms"},
	"quest_complete": {"zh": "客栈介绍完成：前往长安西市", "en": "Inn introduction complete: Go to Chang'an Market"},
	"quest_depart": {"zh": "任务：对腓腓说出发", "en": "Quest: Tell feifei you are ready to go"},
	"quest_hub_choice": {"zh": "任务：说“出发”继续赶路，或说“词灵阁”去玩小游戏", "en": "Quest: Say \"Let's go\" to keep going, or \"Word Spirit Library\" to play"},
	"quest_hub_choice_practice": {"zh": "任务：说“词灵阁”去玩复习小游戏", "en": "Quest: Say \"Word Spirit Library\" to play the review mini-game"},
	"hub_stay": {"zh": "今日已结束", "en": "All done for today"},
	"hub_depart_retry": {"zh": "准备好出发，就对腓腓说：“Let's go!” 或者“出发”。", "en": "When you are ready, say to feifei: \"Let's go!\" or \"出发\"."},
	"hub_choice_retry": {"zh": "想继续赶路，就说“出发”或者“Let's go”；想去词灵阁玩，就说“词灵阁”。", "en": "To keep going, say \"Let's go\". To play in the Word Spirit Library, say \"Word Spirit Library\"."},
	"scroll_retry": {"zh": "对着墙上的画卷说“画中小世界”，它就会听见你。", "en": "Say \"the little world in the painting\" to the scroll on the wall, and it will hear you."},
	"recognizing": {"zh": "正在识别你的声音...", "en": "Listening to your voice..."},
	"coach_waiting": {"zh": "别着急，腓腓来帮你。", "en": "No rush. Feifei will help."},
	"coach_fallback": {"zh": "我们慢慢来。请看着墙上的画卷，清楚地说：画中小世界。", "en": "Let's slow down. Look at the scroll painting on the wall and clearly say: the little world in the painting."},
}

static func loc(key: String, lang: String) -> String:
	if not LOC_STRINGS.has(key):
		return ""
	return str(LOC_STRINGS[key].get(lang, LOC_STRINGS[key].get("zh", "")))

func _loc(key: String) -> String:
	return loc(key, _source_language_code())

func _source_language_code() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.SOURCE_LANGUAGE_CODE)
	return "zh"

func _asr_answer_text(result: Dictionary) -> String:
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
	voice_failure_intervention.set_failure_text_resolver(Callable(self, "_failure_turn_text"))
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

func _failure_turn_text(reason: String) -> String:
	if state == InnIntroState.HUB_AWAIT_CHARGE:
		match reason:
			"silence":
				return "[no_voice_detected] Player did not respond to the formation recharge prompt."
			"asr_error":
				return "[asr_error] Voice service returned an error during the formation recharge prompt."
			"wrong_answer":
				return "[wrong_answer] Player should say the Word Spirit Library entry phrase."
			_:
				return "[voice_retry] Player needs help with the library entry phrase."
	if state == InnIntroState.HUB_AWAIT_CHOICE:
		match reason:
			"silence":
				return "[no_voice_detected] Player did not answer the hub choice: keep going, or practice in the Word Spirit Library."
			"asr_error":
				return "[asr_error] Voice service returned an error during the hub choice prompt."
			"wrong_answer":
				return "[wrong_answer] Player should say Let's go/出发 to keep going, or 词灵阁/书阁 to enter the Word Spirit Library."
			_:
				return "[voice_retry] Player needs help choosing between departure and the Word Spirit Library."

	match reason:
		"silence":
			return "[no_voice_detected] Player did not speak during the scroll voice prompt."
		"asr_error":
			return "[asr_error] Voice service returned an error during the scroll voice prompt."
		"wrong_answer":
			return "[wrong_answer] Player should say the little world in the painting/画中小世界 but said something else."
		_:
			return "[voice_retry] Player needs help saying the little world in the painting/画中小世界."

func _build_scroll_asr_context() -> Dictionary:
	return {
		"session_id": voice_failure_intervention.get_session_id(),
		"user_id": _player_name(),
		"npc_id": "feifei_mirage_inn",
		"scene_id": "mirage_inn_introduction",
		"npc_question": _loc("scroll_retry"),
		"expected_slots": [
			{
				"key": "answer",
				"type": "keyword",
				"description": "玩家对墙上画卷说出的口令：画中小世界/painting",
			}
		],
		"expected_answer_type": "keyword",
		"candidate_answers": ["画中小世界", "little world in the painting", "little world", "painting"],
		"recent_turns": voice_failure_intervention.get_recent_turns(),
		"player_level": _player_level(),
		"language": _source_language_code(),
	}

func _build_hub_choice_asr_context() -> Dictionary:
	return {
		"session_id": voice_failure_intervention.get_session_id(),
		"user_id": _player_name(),
		"npc_id": "feifei_mirage_inn",
		"scene_id": "mirage_inn_hub",
		"npc_question": _hub_choice_question_text(),
		"expected_slots": [
			{
				"key": "answer",
				"type": "keyword",
				"description": "玩家对腓腓说的二选一：Let's go/出发 继续主线，或 词灵阁/书阁/充能 去复习",
			}
		],
		"expected_answer_type": "keyword",
		"candidate_answers": hub_choice_candidates(_hub_departure_available()),
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


func _update_formation_energy_visuals() -> void:
	var manager: Variant = _game_manager()
	var energy: int = 8
	var max_energy: int = 8
	if manager:
		energy = int(manager.get_formation_energy())
		max_energy = int(manager.get_formation_energy_max())
	for i in range(formation_pips.size()):
		var pip: TextureRect = formation_pips[i]
		if i < energy:
			pip.modulate = Color(1.0, 0.86, 0.35, 1.0)
		else:
			pip.modulate = Color(0.22, 0.20, 0.28, 0.55)
	if formation_projection:
		formation_projection.visible = hub_mode
		formation_projection.modulate.a = 0.55 if energy < max_energy else 0.20

func _localized_flow_text(flow_id: String) -> String:
	var flow_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, _source_language_code())
	if flow_lines.is_empty():
		return ""
	return str(flow_lines[0].get("text", ""))

func _is_library_entry_call(text: String) -> bool:
	var lower := text.to_lower()
	for marker in LIBRARY_ENTRY_MARKERS:
		if lower.contains(marker.to_lower()):
			return true
	return false

func _build_library_entry_asr_context() -> Dictionary:
	return {
		"session_id": voice_failure_intervention.get_session_id(),
		"user_id": _player_name(),
		"npc_id": "feifei_mirage_inn",
		"scene_id": "mirage_inn_hub",
		"npc_question": _localized_flow_text("inn_introduction.hub_charge_retry"),
		"expected_slots": [
			{
				"key": "answer",
				"type": "keyword",
				"description": "Word Spirit Library entry command",
			}
		],
		"expected_answer_type": "keyword",
		"candidate_answers": _library_entry_candidates(),
		"recent_turns": voice_failure_intervention.get_recent_turns(),
		"player_level": _player_level(),
		"language": _source_language_code(),
	}

func _handle_hub_charge_asr(result: Dictionary) -> void:
	if result.has("error"):
		await _handle_voice_attempt_failed("asr_error")
		return
	var text := _asr_answer_text(result)
	if await _try_enter_library_from_text(text):
		return
	await _handle_voice_attempt_failed("wrong_answer")

func _enter_word_spirit_library() -> void:
	var library_path: String = GameManager.get_scene_path("WordSpiritLibraryArchiveHall")
	if library_path.is_empty():
		await _speak_flow("inn_introduction.hub_charge_retry", 2.0)
		_start_voice_listening()
		return
	await _fade_to_black()
	var change_result := get_tree().change_scene_to_file(library_path)
	if change_result != OK:
		push_error("[MirageInnHub] Failed to change to WordSpiritLibraryArchiveHall: %s" % error_string(change_result))

func _library_entry_candidates() -> Array[String]:
	return LIBRARY_ENTRY_MARKERS.duplicate()

## 二选一封闭题的候选口令（纯函数，便于单测）：没有可走的主线时只留词灵阁入口——
## 封闭题里混进一个此刻不存在的选项，只会让 ASR 把随口的回答纠成"出发"（CLAUDE.md §9）。
static func hub_choice_candidates(departure_available: bool) -> Array[String]:
	var candidates: Array[String] = []
	if departure_available:
		candidates.append_array(StoryContinueMarkersScript.MARKERS)
	candidates.append_array(LIBRARY_ENTRY_MARKERS)
	return candidates

func _formation_energy_status_text() -> String:
	var manager: Variant = _game_manager()
	var energy: int = 8
	var max_energy: int = 8
	if manager:
		energy = int(manager.get_formation_energy())
		max_energy = int(manager.get_formation_energy_max())
	return "\u9635\u6cd5\u80fd\u91cf: %d/%d" % [energy, max_energy]

func _try_enter_library_from_text(text: String) -> bool:
	if not _is_library_entry_call(text):
		return false
	voice_failure_intervention.reset_failures()
	voice_failure_intervention.add_turn("player", text)
	_stop_voice_listening()
	await _enter_word_spirit_library()
	return true
