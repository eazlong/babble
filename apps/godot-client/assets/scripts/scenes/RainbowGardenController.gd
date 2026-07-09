## 彩虹花园场景控制器
##
## 管理彩虹花园场景的任务流程：
## 1. 修复天气水晶 — 语音说出天气词汇（sunny/rainy/cloudy/snowy），3次
## 2. 找到迷路小动物 — 语音说出动物+位置（cat in tree等），3只
## 3. 种植魔法花朵 — 语音说出动词+颜色（plant red/water blue等），3朵
## 4. 获得 Rainbow Garden Badge → 显示通关 / 返回主菜单
##
extends Node2D

# ——— 任务状态 ———
enum TaskState { NOT_STARTED, IN_PROGRESS, COMPLETED }

var fix_weather_state: TaskState = TaskState.NOT_STARTED
var find_animals_state: TaskState = TaskState.NOT_STARTED
var plant_flowers_state: TaskState = TaskState.NOT_STARTED
var badge_collected: bool = false

# ——— 天气水晶任务配置 ———
const REQUIRED_WEATHER = ["sunny", "rainy", "cloudy", "snowy"]
var fixed_weather: Array[String] = []

# ——— 找动物任务配置 ———
const TARGET_ANIMALS = [
	{"name": "cat", "location": "tree"},
	{"name": "dog", "location": "bridge"},
	{"name": "bird", "location": "bush"}
]
var found_animals: Array[String] = []

# ——— 种花任务配置 ———
const REQUIRED_PLANT_COMBOS = [
	{"verb": "plant", "color": "red"},
	{"verb": "water", "color": "blue"},
	{"verb": "grow", "color": "yellow"}
]
var planted_flowers: Array[String] = []

# ——— 节点引用 ———
@onready var coach_overlay: CoachOverlay = $CoachLayer/CoachOverlay
@onready var mic_panel: Control = $OverlayLayer/MicPanel
@onready var mic_icon: ColorRect = $OverlayLayer/MicPanel/MicIcon
@onready var mic_label: Label = $OverlayLayer/MicPanel/MicLabel
@onready var sunny_npc: Node2D = $SunnyNPC
@onready var flora_npc: Node2D = $FloraNPC
@onready var weather_crystal: Node2D = $WeatherCrystal
@onready var animal_hiding_spot: Node2D = $AnimalHidingSpot
@onready var flower_garden: Node2D = $FlowerGarden
@onready var badge_ui: Control = $OverlayLayer/BadgeUI
@onready var navigation_ui: Control = $OverlayLayer/NavigationUI

# ——— 语音状态 ———
var voice_listening: bool = false
var mic_tween: Tween
var silence_timer: float = 0.0
var record_duration: float = 0.0
var last_player_input: String = ""
const SILENCE_TIMEOUT: float = 15.0
const MAX_RECORD_DURATION: float = 10.0

# ——— 信号 ———
signal task_completed(task_name: String)
signal badge_earned()
signal scene_transition_requested(target_scene: String)

func _ready() -> void:
	if badge_ui:
		badge_ui.visible = false
	if navigation_ui:
		navigation_ui.visible = false

	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.quest_status_received.connect(_on_quest_status)
	HybridAPI.quest_report_received.connect(_on_quest_report)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	VoicePipeline.voice_started.connect(_on_voice_started)

	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.player_response_ready.connect(_on_player_response)

	_init_weather_crystal()
	_init_animal_hiding_spot()
	_init_flower_garden()

	if flora_npc:
		flora_npc.visible = false

	HybridAPI.fetch_quest_status("rainbow_garden")

	await get_tree().create_timer(1.0).timeout
	_start_sunny_introduction()

func _process(delta: float) -> void:
	if not voice_listening:
		return

	if not VoicePipeline.is_listening:
		return

	if VoicePipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
		if record_duration > MAX_RECORD_DURATION:
			VoicePipeline.stop_listening()
			_stop_voice_listening()
	else:
		silence_timer += delta
		record_duration = 0.0
		if silence_timer > SILENCE_TIMEOUT:
			_stop_voice_listening()

func _init_weather_crystal() -> void:
	if not weather_crystal:
		return
	for crystal in weather_crystal.get_children():
		if crystal.has_method("set_state"):
			crystal.set_state("broken")

func _init_animal_hiding_spot() -> void:
	if not animal_hiding_spot:
		return
	for spot in animal_hiding_spot.get_children():
		if spot.has_method("set_state"):
			spot.set_state("hidden")

func _init_flower_garden() -> void:
	if not flower_garden:
		return
	for flower in flower_garden.get_children():
		if flower.has_method("set_state"):
			flower.set_state("unplanted")

func _await_tts(timeout: float = 30.0) -> bool:
	"""Wait for TTS playback to finish. Returns true if completed, false if timed out."""
	var state := {"done": false}
	var cb := func(_duration: float): state["done"] = true
	AudioManager.tts_finished.connect(cb)

	var elapsed := 0.0
	while not state["done"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	AudioManager.tts_finished.disconnect(cb)
	return state["done"]

func _start_sunny_introduction() -> void:
	var greeting = _get_localized_string("sunny_greeting")
	DialogueManager.start_npc_dialogue("sunny", greeting)
	if coach_overlay:
		coach_overlay.show_hint(greeting, "idle")
	HybridAPI.synthesize_tts(greeting, "sunny", GameManager.current_lang)

	var ok = await _await_tts()
	if not ok:
		print("[RainbowGarden] TTS timeout, proceeding anyway")

	fix_weather_state = TaskState.IN_PROGRESS
	_start_fix_weather_task()

func _on_dialogue_started(npc_id: String) -> void:
	print("[RainbowGarden] Dialogue started with: ", npc_id)

func _on_dialogue_ended() -> void:
	print("[RainbowGarden] Dialogue ended")

func _on_player_response(text: String) -> void:
	last_player_input = text
	if fix_weather_state == TaskState.IN_PROGRESS:
		_process_weather_input(text)
		return

	if find_animals_state == TaskState.IN_PROGRESS:
		_process_animal_input(text)
		return

	if plant_flowers_state == TaskState.IN_PROGRESS:
		_process_flower_input(text)
		return

	_stop_voice_listening()

func _on_voice_started() -> void:
	print("[RainbowGarden] _on_voice_started — showing mic panel")
	_show_mic_panel()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[RainbowGarden] _on_voice_ended triggered!")
	if not voice_listening:
		return

	_stop_voice_listening()

	if coach_overlay:
		coach_overlay.show_hint("正在识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_quest_status(result: Dictionary) -> void:
	print("[RainbowGarden] Quest status: ", result)
	var completed_quests: Array = result.get("completed_quest_ids", [])
	var has_badge: bool = result.get("badge_unlocked", false)

	if has_badge:
		_show_badge_unlocked("")
		return

	if completed_quests.has("fix_weather_crystal"):
		fix_weather_state = TaskState.COMPLETED
		if weather_crystal:
			for crystal in weather_crystal.get_children():
				if crystal.has_method("set_state"):
					crystal.set_state("repaired")

	if completed_quests.has("find_lost_animals"):
		find_animals_state = TaskState.COMPLETED
		if animal_hiding_spot:
			for spot in animal_hiding_spot.get_children():
				if spot.has_method("set_state"):
					spot.set_state("found")

	if completed_quests.has("plant_flowers"):
		plant_flowers_state = TaskState.COMPLETED
		if flower_garden:
			for flower in flower_garden.get_children():
				if flower.has_method("set_state"):
					flower.set_state("planted")

	if fix_weather_state == TaskState.COMPLETED and \
			find_animals_state == TaskState.COMPLETED and \
			plant_flowers_state == TaskState.COMPLETED:
		_show_badge_unlocked("")
		return

	if fix_weather_state != TaskState.COMPLETED:
		fix_weather_state = TaskState.IN_PROGRESS
		_start_fix_weather_task()
	elif find_animals_state != TaskState.COMPLETED:
		find_animals_state = TaskState.IN_PROGRESS
		_start_find_animals_task()
	elif plant_flowers_state != TaskState.COMPLETED:
		plant_flowers_state = TaskState.IN_PROGRESS
		_start_plant_flowers_task()

func _on_quest_report(result: Dictionary) -> void:
	print("[RainbowGarden] Quest report result: ", result)
	if result.get("success", false):
		var badge_unlocked = result.get("badge_unlocked", null)
		if badge_unlocked != null and badge_unlocked != "":
			_show_badge_unlocked(str(badge_unlocked))
		var lxp_earned: int = result.get("lxp_earned", 0)
		if lxp_earned > 0:
			GameManager.lxp_score += lxp_earned

func _on_asr_received(result: Dictionary) -> void:
	print("[RainbowGarden] ASR result: ", result)
	var text: String = result.get("text", "")
	if text.is_empty():
		print("[RainbowGarden] ASR text empty")
		if fix_weather_state == TaskState.IN_PROGRESS or \
				find_animals_state == TaskState.IN_PROGRESS or \
				plant_flowers_state == TaskState.IN_PROGRESS:
			_start_voice_listening()
		return

	_on_player_response(text)

func _start_voice_listening() -> void:
	if voice_listening:
		return
	voice_listening = true
	VoicePipeline.start_listening()
	silence_timer = 0.0
	record_duration = 0.0

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	VoicePipeline.stop_listening()
	_hide_mic_panel()
	silence_timer = 0.0
	record_duration = 0.0

func _show_mic_panel() -> void:
	if mic_panel:
		mic_panel.visible = true
		mic_panel.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(mic_panel, "modulate:a", 1.0, 0.3)
		UITweenManager.register_tween("ui_feedback", tween)
		_start_mic_pulse()

func _hide_mic_panel() -> void:
	_stop_mic_pulse()
	if mic_panel:
		var tween = create_tween()
		tween.tween_property(mic_panel, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): mic_panel.visible = false)
		UITweenManager.register_tween("ui_feedback", tween)

func _start_mic_pulse() -> void:
	if not mic_icon:
		return
	_stop_mic_pulse()

	mic_tween = create_tween()
	mic_tween.set_loops()
	mic_tween.tween_property(mic_icon, "color", Color(0.2, 1.0, 0.4, 1.0), 0.6)
	mic_tween.tween_property(mic_icon, "color", Color(0.2, 0.4, 0.2, 1.0), 0.6)
	UITweenManager.register_tween("ui_feedback", mic_tween)

func _stop_mic_pulse() -> void:
	if mic_tween:
		mic_tween.kill()
		mic_tween = null

## ——— Task 1: fix_weather_crystal ———

func _start_fix_weather_task() -> void:
	var instruction = _get_localized_string("fix_weather_instruction")
	DialogueManager.start_npc_dialogue("sunny", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "sunny", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_weather_input(text: String) -> void:
	var lower_text = text.to_lower()
	for weather in REQUIRED_WEATHER:
		if lower_text.contains(weather):
			_fix_weather_crystal(weather)
			return

func _fix_weather_crystal(weather: String) -> void:
	if fixed_weather.has(weather):
		return

	fixed_weather.append(weather)
	print("[RainbowGarden] Fixed weather crystal: ", weather, " (", fixed_weather.size(), "/", REQUIRED_WEATHER.size(), ")")

	if weather_crystal:
		for crystal in weather_crystal.get_children():
			if crystal.has_method("get_weather") and crystal.get_weather() == weather:
				crystal.set_state("repaired")

	if fixed_weather.size() >= 3:
		fix_weather_state = TaskState.COMPLETED
		task_completed.emit("fix_weather_crystal")
		var weather_scores = await HybridAPI.assess_player_input(
			last_player_input, "fix_weather_crystal", "rainbow_garden"
		)
		HybridAPI.report_quest_complete(
			"fix_weather_crystal", "rainbow_garden", weather_scores, last_player_input
		)
		_start_find_animals_task()

## ——— Task 2: find_lost_animals ———

func _start_find_animals_task() -> void:
	find_animals_state = TaskState.IN_PROGRESS
	var instruction = _get_localized_string("find_animals_instruction")
	DialogueManager.start_npc_dialogue("sunny", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "sunny", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_animal_input(text: String) -> void:
	var lower_text = text.to_lower()

	for target in TARGET_ANIMALS:
		var animal_name: String = target["name"]
		var location: String = target["location"]
		if found_animals.has(animal_name):
			continue
		if lower_text.contains(animal_name) and lower_text.contains(location):
			_find_animal(animal_name)
			return

func _find_animal(animal_name: String) -> void:
	found_animals.append(animal_name)
	print("[RainbowGarden] Found animal: ", animal_name, " (", found_animals.size(), "/", TARGET_ANIMALS.size(), ")")

	if animal_hiding_spot:
		for spot in animal_hiding_spot.get_children():
			if spot.has_method("get_animal") and spot.get_animal() == animal_name:
				spot.set_state("found")

	if found_animals.size() >= TARGET_ANIMALS.size():
		find_animals_state = TaskState.COMPLETED
		task_completed.emit("find_lost_animals")
		var animal_scores = await HybridAPI.assess_player_input(
			last_player_input, "find_lost_animals", "rainbow_garden"
		)
		HybridAPI.report_quest_complete(
			"find_lost_animals", "rainbow_garden", animal_scores, last_player_input
		)
		_start_plant_flowers_task()

## ——— Task 3: plant_flowers ———

func _start_plant_flowers_task() -> void:
	plant_flowers_state = TaskState.IN_PROGRESS

	if flora_npc:
		flora_npc.visible = true

	var instruction = _get_localized_string("plant_flowers_instruction")
	DialogueManager.start_npc_dialogue("flora", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "flora", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_flower_input(text: String) -> void:
	var lower_text = text.to_lower()

	for combo in REQUIRED_PLANT_COMBOS:
		var verb: String = combo["verb"]
		var color: String = combo["color"]
		if planted_flowers.has(color):
			continue
		if lower_text.contains(verb) and lower_text.contains(color):
			_plant_flower(verb, color)
			return

func _plant_flower(verb: String, color: String) -> void:
	planted_flowers.append(color)
	print("[RainbowGarden] Planted flower: ", verb, " ", color, " (", planted_flowers.size(), "/", REQUIRED_PLANT_COMBOS.size(), ")")

	if flower_garden:
		for flower in flower_garden.get_children():
			if flower.has_method("get_color") and flower.get_color() == color:
				flower.set_state("planted")

	if planted_flowers.size() >= REQUIRED_PLANT_COMBOS.size():
		plant_flowers_state = TaskState.COMPLETED
		task_completed.emit("plant_flowers")
		var flower_scores = await HybridAPI.assess_player_input(
			last_player_input, "plant_flowers", "rainbow_garden"
		)
		HybridAPI.report_quest_complete(
			"plant_flowers", "rainbow_garden", flower_scores, last_player_input
		)
		_play_celebration()

		await get_tree().create_timer(2.0).timeout
		_award_garden_badge()

func _play_celebration() -> void:
	var celebration = _get_localized_string("celebration")
	DialogueManager.start_npc_dialogue("flora", celebration)

func _show_badge_unlocked(badge_id: String) -> void:
	badge_collected = true
	GameManager.lxp_score += 150
	GameManager.save_progress()

	if badge_ui:
		badge_ui.visible = true
		badge_ui.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(badge_ui, "modulate:a", 1.0, 1.0)
		tween.tween_property(badge_ui, "scale", Vector2(1.2, 1.2), 0.3)
		tween.tween_property(badge_ui, "scale", Vector2(1.0, 1.0), 0.2)
		UITweenManager.register_tween("vfx", tween)

	badge_earned.emit()

	await get_tree().create_timer(3.0).timeout
	if navigation_ui:
		navigation_ui.visible = true

func _award_garden_badge() -> void:
	badge_collected = true
	GameManager.lxp_score += 150
	GameManager.save_progress()

	if badge_ui:
		badge_ui.visible = true
		badge_ui.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(badge_ui, "modulate:a", 1.0, 1.0)
		tween.tween_property(badge_ui, "scale", Vector2(1.2, 1.2), 0.3)
		tween.tween_property(badge_ui, "scale", Vector2(1.0, 1.0), 0.2)
		UITweenManager.register_tween("vfx", tween)

	badge_earned.emit()

	await get_tree().create_timer(3.0).timeout
	if navigation_ui:
		navigation_ui.visible = true

func _on_main_menu_button_pressed() -> void:
	scene_transition_requested.emit("MainMenu")
	get_tree().change_scene_to_file("res://assets/scenes/MainMenu.tscn")

func _get_localized_string(key: String) -> String:
	var is_zh = GameManager.current_lang == "zh"

	var strings = {
		"sunny_greeting": {
			"zh": "你好！我是 Sunny！欢迎来到彩虹花园。天气水晶坏了，你能帮我修复它吗？",
			"en": "Hello! I'm Sunny! Welcome to the Rainbow Garden. The weather crystal is broken, can you help me fix it?"
		},
		"fix_weather_instruction": {
			"zh": "说出天气单词来修复水晶：Sunny、Rainy、Cloudy、Snowy！完成3次就好！",
			"en": "Say weather words to fix the crystal: Sunny, Rainy, Cloudy, Snowy! Complete 3 of them！"
		},
		"find_animals_instruction": {
			"zh": "小动物们迷路了！说出它们的名字和藏身处。Cat in the tree, Dog under the bridge！",
			"en": "The animals are lost! Say their name and where they hide. Cat in the tree, Dog under the bridge！"
		},
		"plant_flowers_instruction": {
			"zh": "你好！我是 Flora。让我教你种魔法花吧！说出动作和颜色：Plant Red, Water Blue, Grow Yellow！",
			"en": "Hello! I'm Flora. Let me teach you to plant magic flowers! Say action and color: Plant Red, Water Blue, Grow Yellow！"
		},
		"celebration": {
			"zh": "太棒了！花园里的花都开了！这是你的彩虹花园徽章！",
			"en": "Amazing! All the flowers are blooming! Here's your Rainbow Garden Badge！"
		},
		"game_complete": {
			"zh": "恭喜你完成了所有冒险！你是语言学习大师！",
			"en": "Congratulations! You completed all adventures! You are a language learning master！"
		}
	}

	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
