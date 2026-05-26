## 精灵森林场景控制器
##
## 管理精灵森林场景的任务流程：
## 1. Spark 自我介绍 → 玩家语音输入名字
## 2. Spark 教问候语 → 遇到 Oakley
## 3. 颜色任务：3 朵魔法花，语音输入颜色激活
## 4. 数字任务：宝箱，语音输入数字解锁
## 5. 获得 Forest Badge → 前往图书馆
##
extends Node2D

# ——— 任务状态 ———
enum TaskState { NOT_STARTED, IN_PROGRESS, COMPLETED }

var name_collection_state: TaskState = TaskState.NOT_STARTED
var color_task_state: TaskState = TaskState.NOT_STARTED
var number_task_state: TaskState = TaskState.NOT_STARTED
var badge_collected: bool = false

# ——— 颜色任务配置 ———
const REQUIRED_COLORS = ["red", "blue", "yellow"]
var activated_colors: Array[String] = []

# ——— 数字任务配置 ———
const TARGET_NUMBER = 7
var number_attempts: int = 0

# ——— 节点引用 ———
@onready var coach_overlay: CoachOverlay = $CoachOverlay
@onready var mic_panel: Control = $MicPanel
@onready var mic_icon: ColorRect = $MicPanel/MicIcon
@onready var mic_label: Label = $MicPanel/MicLabel
@onready var spark_npc: Node2D = $SparkNPC
@onready var oakley_npc: Node2D = $OakleyNPC
@onready var magic_flowers: Node2D = $MagicFlowers
@onready var treasure_chest: Node2D = $TreasureChest
@onready var badge_ui: Control = $BadgeUI
@onready var navigation_ui: Control = $NavigationUI

# ——— 语音状态 ———
var voice_listening: bool = false
var mic_tween: Tween
var silence_timer: float = 0.0
var record_duration: float = 0.0
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
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	VoicePipeline.voice_started.connect(_on_voice_started)

	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.player_response_ready.connect(_on_player_response)

	_init_magic_flowers()
	_init_treasure_chest()

	if oakley_npc:
		oakley_npc.visible = false

	await get_tree().create_timer(1.0).timeout
	_start_spark_introduction()

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

func _init_magic_flowers() -> void:
	if not magic_flowers:
		return
	for flower in magic_flowers.get_children():
		if flower.has_method("set_state"):
			flower.set_state("inactive")

func _init_treasure_chest() -> void:
	if not treasure_chest:
		return
	if treasure_chest.has_method("set_locked"):
		treasure_chest.set_locked(true)

func _await_tts(timeout: float = 30.0) -> bool:
	"""Wait for TTS playback to finish. Returns true if completed, false if timed out."""
	var done := false
	var cb := func(): done = true
	AudioManager.tts_finished.connect(cb)

	var elapsed := 0.0
	while not done and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	AudioManager.tts_finished.disconnect(cb)
	return done

func _start_spark_introduction() -> void:
	var greeting = _get_localized_string("spark_greeting")
	DialogueManager.start_npc_dialogue("spark", greeting)
	if coach_overlay:
		coach_overlay.show_hint(greeting, "idle")
	HybridAPI.synthesize_tts(greeting, "spirit", GameManager.current_lang)

	var ok = await _await_tts()
	if not ok:
		print("[SpiritForest] TTS timeout, proceeding anyway")

	name_collection_state = TaskState.IN_PROGRESS
	_start_voice_listening()

func _on_dialogue_started(npc_id: String) -> void:
	print("[SpiritForest] Dialogue started with: ", npc_id)

func _on_dialogue_ended() -> void:
	print("[SpiritForest] Dialogue ended")
	if name_collection_state == TaskState.IN_PROGRESS:
		name_collection_state = TaskState.COMPLETED
		_start_color_tutorial()

func _on_player_response(text: String) -> void:
	if name_collection_state == TaskState.IN_PROGRESS:
		GameManager.set_player_info(text, 8)
		print("[SpiritForest] Player name set to: ", text)
		name_collection_state = TaskState.COMPLETED
		_stop_voice_listening()
		_start_color_tutorial()
		return

	if color_task_state == TaskState.IN_PROGRESS:
		_process_color_input(text)

	elif number_task_state == TaskState.IN_PROGRESS:
		_process_number_input(text)

	_stop_voice_listening()

func _on_voice_started() -> void:
	print("[SpiritForest] _on_voice_started — showing mic panel")
	_show_mic_panel()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[SpiritForest] _on_voice_ended triggered!")
	if not voice_listening:
		return

	_stop_voice_listening()

	if coach_overlay:
		coach_overlay.show_hint("正在识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_asr_received(result: Dictionary) -> void:
	print("[SpiritForest] ASR result: ", result)
	var text: String = result.get("text", "")
	if text.is_empty():
		print("[SpiritForest] ASR text empty")
		if name_collection_state == TaskState.IN_PROGRESS or color_task_state == TaskState.IN_PROGRESS or number_task_state == TaskState.IN_PROGRESS:
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
		_start_mic_pulse()

func _hide_mic_panel() -> void:
	_stop_mic_pulse()
	if mic_panel:
		var tween = create_tween()
		tween.tween_property(mic_panel, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): mic_panel.visible = false)

func _start_mic_pulse() -> void:
	if not mic_icon:
		return
	_stop_mic_pulse()

	mic_tween = create_tween()
	mic_tween.set_loops()
	mic_tween.tween_property(mic_icon, "color", Color(0.2, 1.0, 0.4, 1.0), 0.6)
	mic_tween.tween_property(mic_icon, "color", Color(0.2, 0.4, 0.2, 1.0), 0.6)

func _stop_mic_pulse() -> void:
	if mic_tween:
		mic_tween.kill()
		mic_tween = null

func _start_color_tutorial() -> void:
	var tutorial = _get_localized_string("color_tutorial")
	DialogueManager.start_npc_dialogue("spark", tutorial)
	if coach_overlay:
		coach_overlay.show_hint(tutorial, "idle")
	HybridAPI.synthesize_tts(tutorial, "spirit", GameManager.current_lang)
	await _await_tts()

	await get_tree().create_timer(3.0).timeout
	_start_color_task()

func _start_color_task() -> void:
	color_task_state = TaskState.IN_PROGRESS
	var instruction = _get_localized_string("color_task_instruction")
	DialogueManager.start_npc_dialogue("spark", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "spirit", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_color_input(text: String) -> void:
	var lower_text = text.to_lower()
	for color in REQUIRED_COLORS:
		if lower_text.contains(color):
			_activate_color_flower(color)
			return

func _activate_color_flower(color: String) -> void:
	if activated_colors.has(color):
		return

	activated_colors.append(color)
	print("[SpiritForest] Activated color: ", color, " (", activated_colors.size(), "/", REQUIRED_COLORS.size(), ")")

	if magic_flowers:
		for flower in magic_flowers.get_children():
			if flower.has_method("get_color") and flower.get_color() == color:
				flower.set_state("active")

	if activated_colors.size() == REQUIRED_COLORS.size():
		color_task_state = TaskState.COMPLETED
		task_completed.emit("color_task")
		_start_oakley_encounter()

func _start_oakley_encounter() -> void:
	if oakley_npc:
		oakley_npc.visible = true

	var oakley_greeting = _get_localized_string("oakley_greeting")
	DialogueManager.start_npc_dialogue("oakley", oakley_greeting)
	if coach_overlay:
		coach_overlay.show_hint(oakley_greeting, "idle")
	HybridAPI.synthesize_tts(oakley_greeting, "spirit", GameManager.current_lang)
	await _await_tts()

	await get_tree().create_timer(3.0).timeout
	_start_number_task()

func _start_number_task() -> void:
	number_task_state = TaskState.IN_PROGRESS
	var instruction = _get_localized_string("number_task_instruction")
	DialogueManager.start_npc_dialogue("oakley", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "spirit", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_number_input(text: String) -> void:
	var numbers = _extract_numbers(text)

	if _contains_chinese_number(text, TARGET_NUMBER):
		_complete_number_task()
		return

	for num in numbers:
		if num == TARGET_NUMBER:
			_complete_number_task()
			return

	number_attempts += 1
	if number_attempts >= 3:
		var hint = _get_localized_string("number_hint")
		DialogueManager.start_npc_dialogue("oakley", hint)
		number_attempts = 0

func _contains_chinese_number(text: String, target: int) -> bool:
	var chinese_numbers = {
		1: ["一", "壹"],
		2: ["二", "两", "贰"],
		3: ["三", "叁"],
		4: ["四", "肆"],
		5: ["五", "伍"],
		6: ["六", "陆"],
		7: ["七", "柒"],
		8: ["八", "捌"],
		9: ["九", "玖"],
		10: ["十", "拾"]
	}

	if chinese_numbers.has(target):
		for variant in chinese_numbers[target]:
			if text.contains(variant):
				return true
	return false

func _extract_numbers(text: String) -> Array[int]:
	var numbers: Array[int] = []

	var current_number = ""
	for char in text:
		if char >= "0" and char <= "9":
			current_number += char
		else:
			if current_number.length() > 0:
				numbers.append(int(current_number))
				current_number = ""

	if current_number.length() > 0:
		numbers.append(int(current_number))

	return numbers

func _complete_number_task() -> void:
	number_task_state = TaskState.COMPLETED
	task_completed.emit("number_task")

	if treasure_chest:
		treasure_chest.set_locked(false)

	_play_celebration()

	await get_tree().create_timer(2.0).timeout
	_award_forest_badge()

func _play_celebration() -> void:
	var celebration = _get_localized_string("celebration")
	DialogueManager.start_npc_dialogue("oakley", celebration)

func _award_forest_badge() -> void:
	badge_collected = true
	GameManager.unlocked_areas.append("SpellLibrary")
	GameManager.lxp_score += 100
	GameManager.save_progress()

	if badge_ui:
		badge_ui.visible = true
		badge_ui.modulate.a = 0
		var tween = create_tween()
		tween.tween_property(badge_ui, "modulate:a", 1.0, 1.0)
		tween.tween_property(badge_ui, "scale", Vector2(1.2, 1.2), 0.3)
		tween.tween_property(badge_ui, "scale", Vector2(1.0, 1.0), 0.2)

	badge_earned.emit()

	await get_tree().create_timer(3.0).timeout
	if navigation_ui:
		navigation_ui.visible = true

func _on_library_button_pressed() -> void:
	scene_transition_requested.emit("SpellLibrary")
	get_tree().change_scene_to_file("res://assets/scenes/SpellLibrary.tscn")

func _get_localized_string(key: String) -> String:
	var is_zh = GameManager.current_lang == "zh"

	var strings = {
		"spark_greeting": {
			"zh": "你好！我是 Spark，你的语言学习伙伴！你叫什么名字呢？",
			"en": "Hello! I'm Spark, your language learning companion! What's your name?"
		},
		"color_tutorial": {
			"zh": "让我教你颜色魔法吧！红色是 Red，蓝色是 Blue，黄色是 Yellow！",
			"en": "Let me teach you color magic! Red is 红色，Blue is 蓝色，Yellow is 黄色！"
		},
		"color_task_instruction": {
			"zh": "现在请用颜色咒语激活魔法花吧！说出 Red、Blue 或 Yellow！",
			"en": "Now use color spells to activate the magic flowers! Say Red, Blue, or Yellow！"
		},
		"oakley_greeting": {
			"zh": "你好，小魔法师！我是 Oakley，森林守护者。你能帮我数清楚这里有多少个蘑菇吗？",
			"en": "Hello, little mage! I'm Oakley, the forest guardian. Can you count how many mushrooms are here?"
		},
		"number_task_instruction": {
			"zh": "仔细数一数，然后告诉我数字！",
			"en": "Count carefully, then tell me the number！"
		},
		"number_hint": {
			"zh": "提示：比 5 多，比 10 少，再数一次试试看！",
			"en": "Hint: More than 5, less than 10. Try counting again！"
		},
		"celebration": {
			"zh": "太棒了！你解开了宝箱！这是你的森林徽章！",
			"en": "Amazing! You unlocked the treasure chest! Here's your Forest Badge！"
		}
	}

	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
