## 咒语图书馆场景控制器
##
## 管理咒语图书馆场景的任务流程：
## 1. NPC Luna 介绍图书馆 → 语音整理书籍（big/small/颜色分类，3次）
## 2. NPC Teacher 给出课堂指令 → 语音回应/执行（3个指令）
## 3. Luna 对话练习 → 自由问答（3轮）
## 4. 获得 Library Badge → 解锁 RainbowGarden 场景
##
extends Node2D

# ——— 任务状态 ———
enum TaskState { NOT_STARTED, IN_PROGRESS, COMPLETED }

var organize_books_state: TaskState = TaskState.NOT_STARTED
var follow_commands_state: TaskState = TaskState.NOT_STARTED
var practice_dialogue_state: TaskState = TaskState.NOT_STARTED
var badge_collected: bool = false

# ——— 整理书籍任务配置 ———
const REQUIRED_CATEGORIES = ["big", "small", "red"]
var organized_books: Array[String] = []

# ——— 课堂指令任务配置 ———
const TARGET_COMMANDS = ["stand up", "open the book", "read aloud"]
var completed_commands: Array[String] = []

# ——— 对话练习任务配置 ———
const REQUIRED_DIALOGUE_ROUNDS = 3
var dialogue_rounds_completed: int = 0
var current_dialogue_index: int = 0

# ——— 节点引用 ———
@onready var coach_overlay: CoachOverlay = $CoachOverlay
@onready var mic_panel: Control = $MicPanel
@onready var mic_icon: ColorRect = $MicPanel/MicIcon
@onready var mic_label: Label = $MicPanel/MicLabel
@onready var luna_npc: Node2D = $LunaNPC
@onready var teacher_npc: Node2D = $TeacherNPC
@onready var bookshelf: Node2D = $Bookshelf
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
	HybridAPI.quest_status_received.connect(_on_quest_status)
	HybridAPI.quest_report_received.connect(_on_quest_report)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	VoicePipeline.voice_started.connect(_on_voice_started)

	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.player_response_ready.connect(_on_player_response)

	_init_bookshelf()

	HybridAPI.fetch_quest_status("spell_library")

	await get_tree().create_timer(1.0).timeout
	_start_luna_introduction()

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

func _init_bookshelf() -> void:
	if not bookshelf:
		return
	for book in bookshelf.get_children():
		if book.has_method("set_state"):
			book.set_state("unsorted")

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

func _start_luna_introduction() -> void:
	var greeting = _get_localized_string("luna_greeting")
	DialogueManager.start_npc_dialogue("luna", greeting)
	if coach_overlay:
		coach_overlay.show_hint(greeting, "idle")
	HybridAPI.synthesize_tts(greeting, "luna", GameManager.current_lang)

	var ok = await _await_tts()
	if not ok:
		print("[SpellLibrary] TTS timeout, proceeding anyway")

	organize_books_state = TaskState.IN_PROGRESS
	_start_organize_books_task()

func _on_dialogue_started(npc_id: String) -> void:
	print("[SpellLibrary] Dialogue started with: ", npc_id)

func _on_dialogue_ended() -> void:
	print("[SpellLibrary] Dialogue ended")

func _on_player_response(text: String) -> void:
	if organize_books_state == TaskState.IN_PROGRESS:
		_process_book_input(text)
		return

	if follow_commands_state == TaskState.IN_PROGRESS:
		_process_command_input(text)
		return

	if practice_dialogue_state == TaskState.IN_PROGRESS:
		_process_dialogue_response(text)
		return

	_stop_voice_listening()

func _on_voice_started() -> void:
	print("[SpellLibrary] _on_voice_started — showing mic panel")
	_show_mic_panel()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[SpellLibrary] _on_voice_ended triggered!")
	if not voice_listening:
		return

	_stop_voice_listening()

	if coach_overlay:
		coach_overlay.show_hint("正在识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_quest_status(result: Dictionary) -> void:
	print("[SpellLibrary] Quest status: ", result)
	var completed_quests: Array = result.get("completed_quest_ids", [])
	var has_badge: bool = result.get("badge_unlocked", false)

	if has_badge:
		_show_badge_unlocked("")
		return

	if completed_quests.has("organize_books"):
		organize_books_state = TaskState.COMPLETED
		if bookshelf:
			for book in bookshelf.get_children():
				if book.has_method("set_state"):
					book.set_state("sorted")

	if completed_quests.has("follow_commands"):
		follow_commands_state = TaskState.COMPLETED

	if completed_quests.has("practice_dialogue"):
		practice_dialogue_state = TaskState.COMPLETED

	if organize_books_state == TaskState.COMPLETED and \
			follow_commands_state == TaskState.COMPLETED and \
			practice_dialogue_state == TaskState.COMPLETED:
		_show_badge_unlocked("")
		return

	if organize_books_state != TaskState.COMPLETED:
		organize_books_state = TaskState.IN_PROGRESS
		_start_organize_books_task()
	elif follow_commands_state != TaskState.COMPLETED:
		follow_commands_state = TaskState.IN_PROGRESS
		_start_follow_commands_task()
	elif practice_dialogue_state != TaskState.COMPLETED:
		practice_dialogue_state = TaskState.IN_PROGRESS
		_start_practice_dialogue_task()

func _on_quest_report(result: Dictionary) -> void:
	print("[SpellLibrary] Quest report result: ", result)
	if result.get("success", false):
		var badge_unlocked = result.get("badge_unlocked", null)
		if badge_unlocked != null and badge_unlocked != "":
			_show_badge_unlocked(str(badge_unlocked))
		var lxp_earned: int = result.get("lxp_earned", 0)
		if lxp_earned > 0:
			GameManager.lxp_score += lxp_earned

func _on_asr_received(result: Dictionary) -> void:
	print("[SpellLibrary] ASR result: ", result)
	var text: String = result.get("text", "")
	if text.is_empty():
		print("[SpellLibrary] ASR text empty")
		if organize_books_state == TaskState.IN_PROGRESS or \
				follow_commands_state == TaskState.IN_PROGRESS or \
				practice_dialogue_state == TaskState.IN_PROGRESS:
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

## ——— Task 1: organize_books ———

func _start_organize_books_task() -> void:
	var instruction = _get_localized_string("organize_books_instruction")
	DialogueManager.start_npc_dialogue("luna", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "luna", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_book_input(text: String) -> void:
	var lower_text = text.to_lower()
	for category in REQUIRED_CATEGORIES:
		if lower_text.contains(category):
			_organize_book(category)
			return

func _organize_book(category: String) -> void:
	if organized_books.has(category):
		return

	organized_books.append(category)
	print("[SpellLibrary] Organized book category: ", category, " (", organized_books.size(), "/", REQUIRED_CATEGORIES.size(), ")")

	if bookshelf:
		for book in bookshelf.get_children():
			if book.has_method("get_category") and book.get_category() == category:
				book.set_state("sorted")

	if organized_books.size() == REQUIRED_CATEGORIES.size():
		organize_books_state = TaskState.COMPLETED
		task_completed.emit("organize_books")
		HybridAPI.report_quest_complete(
			"organize_books", "spell_library",
			{"accuracy": 90, "fluency": 70, "vocabulary": 85}
		)
		_start_follow_commands_task()

## ——— Task 2: follow_commands ———

func _start_follow_commands_task() -> void:
	follow_commands_state = TaskState.IN_PROGRESS
	var instruction = _get_localized_string("follow_commands_intro")
	DialogueManager.start_npc_dialogue("teacher", instruction)
	if coach_overlay:
		coach_overlay.show_hint(instruction, "idle")
	HybridAPI.synthesize_tts(instruction, "teacher", GameManager.current_lang)
	await _await_tts()
	_issue_next_command()

func _issue_next_command() -> void:
	var cmd_index = completed_commands.size()
	if cmd_index >= TARGET_COMMANDS.size():
		_complete_follow_commands()
		return

	var command_key = "command_" + str(cmd_index)
	var command = _get_localized_string(command_key)
	DialogueManager.start_npc_dialogue("teacher", command)
	if coach_overlay:
		coach_overlay.show_hint(command, "idle")
	HybridAPI.synthesize_tts(command, "teacher", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_command_input(text: String) -> void:
	var lower_text = text.to_lower()

	var expected_cmd = TARGET_COMMANDS[completed_commands.size()]
	if lower_text.contains(expected_cmd):
		completed_commands.append(expected_cmd)
		print("[SpellLibrary] Command completed: ", expected_cmd, " (", completed_commands.size(), "/", TARGET_COMMANDS.size(), ")")
		_stop_voice_listening()
		await get_tree().create_timer(1.0).timeout
		_issue_next_command()
		return

	# Wrong command — give hint after 3 attempts
	if completed_commands.size() < TARGET_COMMANDS.size():
		_stop_voice_listening()
		await get_tree().create_timer(1.0).timeout
		var hint = _get_localized_string("command_hint")
		DialogueManager.start_npc_dialogue("teacher", hint)
		if coach_overlay:
			coach_overlay.show_hint(hint, "idle")
		HybridAPI.synthesize_tts(hint, "teacher", GameManager.current_lang)
		await _await_tts()
		_issue_next_command()

func _complete_follow_commands() -> void:
	follow_commands_state = TaskState.COMPLETED
	task_completed.emit("follow_commands")
	HybridAPI.report_quest_complete(
		"follow_commands", "spell_library",
		{"accuracy": 85, "fluency": 80, "vocabulary": 90}
	)
	_start_practice_dialogue_task()

## ——— Task 3: practice_dialogue ———

func _start_practice_dialogue_task() -> void:
	practice_dialogue_state = TaskState.IN_PROGRESS
	var intro = _get_localized_string("dialogue_intro")
	DialogueManager.start_npc_dialogue("luna", intro)
	if coach_overlay:
		coach_overlay.show_hint(intro, "idle")
	HybridAPI.synthesize_tts(intro, "luna", GameManager.current_lang)
	await _await_tts()
	_ask_next_question()

func _ask_next_question() -> void:
	if dialogue_rounds_completed >= REQUIRED_DIALOGUE_ROUNDS:
		_complete_practice_dialogue()
		return

	var question_key = "dialogue_question_" + str(current_dialogue_index)
	var question = _get_localized_string(question_key)
	if question.is_empty():
		question = _get_localized_string("dialogue_fallback")
	DialogueManager.start_npc_dialogue("luna", question)
	if coach_overlay:
		coach_overlay.show_hint(question, "idle")
	HybridAPI.synthesize_tts(question, "luna", GameManager.current_lang)
	await _await_tts()
	_start_voice_listening()

func _process_dialogue_response(text: String) -> void:
	dialogue_rounds_completed += 1
	current_dialogue_index += 1
	print("[SpellLibrary] Dialogue round: ", dialogue_rounds_completed, "/", REQUIRED_DIALOGUE_ROUNDS)
	_stop_voice_listening()
	await get_tree().create_timer(1.0).timeout
	_ask_next_question()

func _complete_practice_dialogue() -> void:
	practice_dialogue_state = TaskState.COMPLETED
	task_completed.emit("practice_dialogue")
	HybridAPI.report_quest_complete(
		"practice_dialogue", "spell_library",
		{"accuracy": 80, "fluency": 85, "vocabulary": 80}
	)
	_play_celebration()

	await get_tree().create_timer(2.0).timeout
	_award_library_badge()

func _play_celebration() -> void:
	var celebration = _get_localized_string("celebration")
	DialogueManager.start_npc_dialogue("luna", celebration)

func _show_badge_unlocked(badge_id: String) -> void:
	badge_collected = true
	GameManager.unlocked_areas.append("RainbowGarden")
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

func _award_library_badge() -> void:
	badge_collected = true
	GameManager.unlocked_areas.append("RainbowGarden")
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

func _on_rainbow_garden_button_pressed() -> void:
	scene_transition_requested.emit("RainbowGarden")
	get_tree().change_scene_to_file("res://assets/scenes/RainbowGarden.tscn")

func _get_localized_string(key: String) -> String:
	var is_zh = GameManager.current_lang == "zh"

	var strings = {
		"luna_greeting": {
			"zh": "你好！我是 Luna，图书馆的小管理员！欢迎来到咒语图书馆！",
			"en": "Hello! I'm Luna, the library assistant! Welcome to the Spell Library！"
		},
		"organize_books_instruction": {
			"zh": "图书馆的魔法书都乱了！请帮我把它们整理好。说出 Big Book、Small Book 或者颜色来分类！",
			"en": "The magic books are all messy! Help me organize them. Say Big Book, Small Book, or a color to sort them！"
		},
		"follow_commands_intro": {
			"zh": "我是 Teacher！现在我们来玩课堂指令游戏，听我说然后做！",
			"en": "I'm Teacher! Now let's play a classroom command game. Listen to me and follow along！"
		},
		"command_0": {
			"zh": "请起立！大声说 Stand Up！",
			"en": "Please stand up! Say Stand Up！"
		},
		"command_1": {
			"zh": "请打开你的魔法书！说 Open The Book！",
			"en": "Please open your magic book! Say Open The Book！"
		},
		"command_2": {
			"zh": "请大声朗读！说 Read Aloud！",
			"en": "Please read out loud! Say Read Aloud！"
		},
		"command_hint": {
			"zh": "没关系，我们试试下一个指令吧！",
			"en": "That's okay, let's try the next command！"
		},
		"dialogue_intro": {
			"zh": "太好了！现在让我们和 Luna 聊聊天吧！",
			"en": "Great! Now let's have a chat with Luna！"
		},
		"dialogue_question_0": {
			"zh": "你最喜欢图书馆里的什么书呢？",
			"en": "What is your favorite book in the library?"
		},
		"dialogue_question_1": {
			"zh": "你最喜欢的颜色是什么？为什么？",
			"en": "What is your favorite color? Why?"
		},
		"dialogue_question_2": {
			"zh": "如果让你写一本魔法书，你会写什么呢？",
			"en": "If you could write a magic book, what would it be about?"
		},
		"dialogue_fallback": {
			"zh": "告诉我更多你的想法吧！",
			"en": "Tell me more about what you think！"
		},
		"celebration": {
			"zh": "太棒了！你完成了所有咒语任务！这是你的图书馆徽章！",
			"en": "Amazing! You completed all the spell quests! Here's your Library Badge！"
		}
	}

	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
