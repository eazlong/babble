## 精灵森林第一人称版场景控制器
##
## 任务流程（基于节点导航）：
## 1. 节点A(入口): Spark肩膀精灵欢迎 → 导航到B
## 2. 节点B(大树前): TreeSpirit打招呼 → 玩家说名字 → 评估
## 3. 节点C(花丛): 颜色任务（red/blue/yellow）→ 激活花朵
## 4. 节点D(小溪): 数字任务（数蘑菇）→ 说数字
## 5. 节点E(宝箱): 解锁宝箱 → 获得Forest Badge → 导航到SpellLibrary
##
extends Node2D

# ——— 任务状态 ———
enum TaskState { NOT_STARTED, IN_PROGRESS, COMPLETED }

var name_task_state: TaskState = TaskState.NOT_STARTED
var color_task_state: TaskState = TaskState.NOT_STARTED
var number_task_state: TaskState = TaskState.NOT_STARTED
var badge_collected: bool = false

# ——— 颜色任务 ———
const REQUIRED_COLORS: Array[String] = ["red", "blue", "yellow"]
var activated_colors: Array[String] = []

# ——— 数字任务 ———
const TARGET_NUMBER: int = 7
var number_attempts: int = 0

# ——— 节点引用 ———
@onready var navigator: FirstPersonNavigator = $FirstPersonNavigator
@onready var spark: SparkShoulder = $SparkLayer/SparkShoulder
@onready var tree_spirit: Node2D = $MidLayer/TreeSpirit
@onready var tree_spirit_eyes: Node2D = $MidLayer/TreeSpirit/Eyes
@onready var tree_spirit_eyes_closed: Sprite2D = $MidLayer/TreeSpirit/Eyes/EyesClosed
@onready var tree_spirit_eyes_open: Node2D = $MidLayer/TreeSpirit/Eyes/EyesOpen
@onready var tree_spirit_anim: AnimationPlayer = $MidLayer/TreeSpirit/AnimationPlayer
@onready var watering_can: Sprite2D = $MidLayer/PropsLayer/WateringCan
@onready var watering_can_anim: AnimationPlayer = $MidLayer/PropsLayer/WateringCan/WateringCanAnim
@onready var camera_system: Node2D = $CameraSystem
@onready var main_camera: Camera2D = $CameraSystem/MainCamera
@onready var camera_animator: AnimationPlayer = $CameraSystem/CameraAnimator
@onready var learning_scene: Node2D = $LearningScene
@onready var flower_red: Node2D = $MidLayer/MagicFlowers/RedFlower
@onready var flower_blue: Node2D = $MidLayer/MagicFlowers/BlueFlower
@onready var flower_yellow: Node2D = $MidLayer/MagicFlowers/YellowFlower
@onready var treasure_chest: Node2D = $MidLayer/TreasureChest
@onready var star_bar: Control = $HUDLayer/StarBar
@onready var quest_tracker: Control = $HUDLayer/QuestTracker
@onready var mic_button: Control = $HUDLayer/MicButton
@onready var magic_compass: Control = $HUDLayer/MagicCompass
@onready var badge_ui: Control = $OverlayLayer/BadgeUI
@onready var mid_layer: Node2D = $MidLayer

# ——— 语音状态 ———
var voice_listening: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
var last_player_input: String = ""
var _tree_bubble: Label = null
var _badge_transition_started: bool = false
const SILENCE_TIMEOUT: float = 15.0
const MAX_RECORD_DURATION: float = 10.0

# ——— 信号 ———
signal task_completed(task_name: String)
signal badge_earned()

# ——— 生命周期 ———

func _ready() -> void:
	if badge_ui:
		badge_ui.visible = false

	# 初始化新场景元素
	if tree_spirit_eyes_closed:
		tree_spirit_eyes_closed.visible = true  # 默认闭眼
	if tree_spirit_eyes_open:
		tree_spirit_eyes_open.visible = false
	if watering_can:
		watering_can.visible = false
	if learning_scene:
		learning_scene.visible = false

	# 连接信号
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.quest_status_received.connect(_on_quest_status)
	HybridAPI.quest_report_received.connect(_on_quest_report)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	VoicePipeline.voice_started.connect(_on_voice_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.player_response_ready.connect(_on_player_response)

	if navigator:
		navigator.transition_completed.connect(_on_node_arrived)
		navigator.transition_started.connect(_on_transition_started)

	# 初始化场景元素
	_hide_interactive_elements()
	_init_flowers()

	# 获取任务状态
	HybridAPI.fetch_quest_status("spirit_forest")

	# 开场：Spark欢迎 → 引导到节点B
	await get_tree().create_timer(1.0).timeout
	_start_welcome_sequence()

func _process(delta: float) -> void:
	_process_eye_tracking()

	if not voice_listening or not VoicePipeline.is_listening:
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

# ——— 场景初始化 ———

func _hide_interactive_elements() -> void:
	# 花朵和宝箱初始不可见，按任务进度显示
	for flower in [flower_red, flower_blue, flower_yellow]:
		if flower:
			flower.visible = false
	if treasure_chest:
		treasure_chest.visible = false
	if watering_can:
		watering_can.visible = false

func _init_flowers() -> void:
	for flower in [flower_red, flower_blue, flower_yellow]:
		if flower and flower.has_method("set_state"):
			flower.set_state("inactive")

# ——— 开场欢迎序列 ———

func _start_welcome_sequence() -> void:
	if badge_collected:
		return

	# Spark 从远处飞入屏幕中央
	if spark:
		spark.visible = false
		await get_tree().create_timer(0.5).timeout
		await spark.play_entry_fly_in()

	# 到达屏幕中央后开始说话
	var greeting: String = _loc("spark_greeting")
	if spark:
		spark.show_hint(greeting, SparkShoulder.STATE_HINT, 0)

	HybridAPI.synthesize_tts(greeting, "spirit", GameManager.current_lang)
	await _await_tts()

	if spark:
		spark.go_idle()

	# 说完后 Spark 滑落到肩膀
	if spark:
		await spark.settle_to_shoulder()

	# 等待后自动导航到节点B（TreeSpirit）
	await get_tree().create_timer(2.0).timeout
	if navigator:
		navigator.navigate_to(navigator.FPNode.B_TREE)

# ——— 节点过渡处理 ———

func _on_transition_started(from_node: FirstPersonNavigator.FPNode, to_node: FirstPersonNavigator.FPNode) -> void:
	if to_node == FirstPersonNavigator.FPNode.B_TREE:
		_play_zoom_in_to_tree()

## 过渡到大树前时，从远处拉近的 zoom-in 动画
func _play_zoom_in_to_tree() -> void:
	if not mid_layer:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = viewport_size / 2.0
	var start_scale: float = 0.6

	# 设置初始缩放和偏移，使缩放以屏幕中心为原点
	mid_layer.scale = Vector2(start_scale, start_scale)
	mid_layer.position = center * (1.0 - start_scale)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(mid_layer, "scale", Vector2.ONE, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mid_layer, "position", Vector2.ZERO, 1.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

# ——— 节点到达处理 ———

func _on_node_arrived(node: FirstPersonNavigator.FPNode) -> void:
	print("[SpiritForestFP] Arrived at node: ", FirstPersonNavigator.NODE_NAMES[node])
	match node:
		navigator.FPNode.B_TREE:
			_on_arrive_tree()
		navigator.FPNode.C_FLOWERS:
			_on_arrive_flowers()
		navigator.FPNode.D_STREAM:
			_on_arrive_stream()
		navigator.FPNode.E_CHEST:
			_on_arrive_chest()

func _on_arrive_tree() -> void:
	_set_quest_text(_loc("quest_name"))
	_set_compass_label("→")

	# TreeSpirit显示并睁眼
	if tree_spirit:
		tree_spirit.visible = true

	await get_tree().create_timer(0.5).timeout
	_open_tree_eyes()

	if name_task_state == TaskState.COMPLETED:
		await get_tree().create_timer(0.6).timeout
		_navigate_to_next_node()
		return

	await get_tree().create_timer(0.8).timeout
	var tree_greeting: String = _loc("tree_greeting")
	_show_tree_spirit_bubble(tree_greeting)
	HybridAPI.synthesize_tts(tree_greeting, "spirit", GameManager.current_lang)
	await _await_tts()

	_hide_tree_spirit_bubble()

	# 开始收集名字
	name_task_state = TaskState.IN_PROGRESS
	_start_voice_listening()

func _on_arrive_flowers() -> void:
	_set_quest_text(_loc("quest_colors"))
	_set_compass_label("→")

	# 显示花朵
	_show_all_flowers()

	if color_task_state == TaskState.COMPLETED:
		_mark_all_flowers_active()
		await get_tree().create_timer(0.6).timeout
		_navigate_to_next_node()
		return

	if spark:
		spark.show_hint(_loc("color_instruction"), SparkShoulder.STATE_HINT)

	await get_tree().create_timer(1.5).timeout
	color_task_state = TaskState.IN_PROGRESS
	_start_voice_listening()

func _on_arrive_stream() -> void:
	_set_quest_text(_loc("quest_number"))
	_set_compass_label("↘")

	if number_task_state == TaskState.COMPLETED:
		await get_tree().create_timer(0.6).timeout
		_navigate_to_next_node()
		return

	if spark:
		spark.show_hint(_loc("number_instruction"), SparkShoulder.STATE_HINT)

	await get_tree().create_timer(1.5).timeout
	number_task_state = TaskState.IN_PROGRESS
	_start_voice_listening()

func _on_arrive_chest() -> void:
	_set_quest_text(_loc("quest_badge"))
	_set_compass_label("✓")

	if badge_collected:
		return

	if treasure_chest:
		treasure_chest.visible = true
	# 宝箱打开
	await get_tree().create_timer(0.5).timeout
	if treasure_chest and treasure_chest.has_method("set_locked"):
		treasure_chest.set_locked(false)
	await _award_badge()

# ——— 对话结束回调 ———

func _on_dialogue_ended() -> void:
	if name_task_state == TaskState.IN_PROGRESS and not last_player_input.is_empty():
		name_task_state = TaskState.COMPLETED
		_navigate_to_next_node()

# ——— 玩家输入处理 ———

func _on_player_response(text: String) -> void:
	last_player_input = text

	if name_task_state == TaskState.IN_PROGRESS:
		GameManager.set_player_info(text, 8)
		name_task_state = TaskState.COMPLETED
		var scores = await HybridAPI.assess_player_input(text, "greet_oakley", "spirit_forest")
		HybridAPI.report_quest_complete("greet_oakley", "spirit_forest", scores, text)
		_stop_voice_listening()
		if spark:
			spark.play_happy()
		# 导航到花丛
		await get_tree().create_timer(2.0).timeout
		_navigate_to_next_node()
		return

	if color_task_state == TaskState.IN_PROGRESS:
		await _process_color_input(text)
	elif number_task_state == TaskState.IN_PROGRESS:
		await _process_number_input(text)

func _process_color_input(text: String) -> void:
	var lower_text: String = text.to_lower()
	for color in REQUIRED_COLORS:
		if lower_text.contains(color):
			await _activate_flower(color)
			return

	if spark:
		spark.show_hint(_loc("color_retry"), SparkShoulder.STATE_HINT)
	await get_tree().create_timer(0.8).timeout
	await _continue_voice_listening()

func _activate_flower(color: String) -> void:
	if activated_colors.has(color):
		if color_task_state == TaskState.IN_PROGRESS:
			await _continue_voice_listening()
		return
	activated_colors.append(color)

	var flower: Node2D = _get_flower_by_color(color)
	if flower and flower.has_method("set_state"):
		flower.set_state("active")

	if spark:
		spark.play_happy()

	if activated_colors.size() == REQUIRED_COLORS.size():
		_stop_voice_listening()
		color_task_state = TaskState.COMPLETED
		task_completed.emit("color_task")
		var scores = await HybridAPI.assess_player_input(
			last_player_input, "activate_flowers", "spirit_forest"
		)
		HybridAPI.report_quest_complete("activate_flowers", "spirit_forest", scores, last_player_input)
		# 导航到小溪
		await get_tree().create_timer(2.0).timeout
		_navigate_to_next_node()
	else:
		await get_tree().create_timer(0.8).timeout
		if spark:
			spark.show_hint(_loc("color_progress"), SparkShoulder.STATE_HINT)
		await _continue_voice_listening()

func _process_number_input(text: String) -> void:
	var numbers: Array[int] = _extract_numbers(text)
	if _contains_chinese_number(text, TARGET_NUMBER):
		await _complete_number_task()
		return
	for num in numbers:
		if num == TARGET_NUMBER:
			await _complete_number_task()
			return

	number_attempts += 1
	if spark:
		var hint_key := "number_hint" if number_attempts >= 3 else "number_retry"
		spark.show_hint(_loc(hint_key), SparkShoulder.STATE_HINT)
	if number_attempts >= 3:
		number_attempts = 0
	await get_tree().create_timer(0.8).timeout
	await _continue_voice_listening()

func _complete_number_task() -> void:
	_stop_voice_listening()
	number_task_state = TaskState.COMPLETED
	task_completed.emit("number_task")

	var scores = await HybridAPI.assess_player_input(
		last_player_input, "open_chest", "spirit_forest"
	)
	HybridAPI.report_quest_complete("open_chest", "spirit_forest", scores, last_player_input)

	if spark:
		spark.play_happy()

	# 导航到宝箱
	await get_tree().create_timer(2.0).timeout
	_navigate_to_next_node()

# ——— 导航辅助 ———

func _navigate_to_next_node() -> void:
	if not navigator:
		return
	var current: FirstPersonNavigator.FPNode = navigator.get_current_node()
	var next_node: FirstPersonNavigator.FPNode

	match current:
		navigator.FPNode.A_ENTRY:
			next_node = navigator.FPNode.B_TREE
		navigator.FPNode.B_TREE:
			next_node = navigator.FPNode.C_FLOWERS
		navigator.FPNode.C_FLOWERS:
			next_node = navigator.FPNode.D_STREAM
		navigator.FPNode.D_STREAM:
			next_node = navigator.FPNode.E_CHEST
		_:
			return

	navigator.navigate_to(next_node)

# ——— 语音控制 ———

func _start_voice_listening() -> void:
	if voice_listening:
		return
	voice_listening = true
	VoicePipeline.start_listening()
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = true

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	VoicePipeline.stop_listening()
	silence_timer = 0.0
	record_duration = 0.0
	if mic_button:
		mic_button.visible = false

func _continue_voice_listening() -> void:
	_stop_voice_listening()
	await get_tree().create_timer(0.1).timeout
	_start_voice_listening()

func _on_voice_started() -> void:
	print("[SpiritForestFP] Voice started")

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if not voice_listening:
		return
	_stop_voice_listening()
	if spark:
		spark.show_hint("正在识别...", SparkShoulder.STATE_HINT)
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_asr_received(result: Dictionary) -> void:
	var text: String = result.get("text", "")
	if text.is_empty():
		if name_task_state == TaskState.IN_PROGRESS or \
			color_task_state == TaskState.IN_PROGRESS or \
			number_task_state == TaskState.IN_PROGRESS:
			_start_voice_listening()
		return
	await _on_player_response(text)

# ——— 任务状态同步 ———

func _on_quest_status(result: Dictionary) -> void:
	var completed: Array = result.get("completed_quest_ids", [])
	var has_badge: bool = result.get("badge_unlocked", false)

	if has_badge:
		badge_collected = true
		await _show_badge_ui()
		return

	if completed.has("greet_oakley"):
		name_task_state = TaskState.COMPLETED
	if completed.has("activate_flowers"):
		color_task_state = TaskState.COMPLETED
		activated_colors = REQUIRED_COLORS.duplicate()
	if completed.has("open_chest"):
		number_task_state = TaskState.COMPLETED

func _on_quest_report(result: Dictionary) -> void:
	if result.get("success", false):
		var lxp: int = result.get("lxp_earned", 0)
		if lxp > 0:
			GameManager.lxp_score += lxp

# ——— Badge ———

func _award_badge() -> void:
	if badge_collected:
		return
	badge_collected = true
	if not GameManager.unlocked_areas.has("SpellLibrary"):
		GameManager.unlocked_areas.append("SpellLibrary")
	GameManager.lxp_score += 100
	GameManager.save_progress()
	badge_earned.emit()
	await _show_badge_ui()

func _show_badge_ui() -> void:
	if _badge_transition_started:
		return
	if not badge_ui:
		return
	_badge_transition_started = true
	_set_quest_text(_loc("badge_earned"))
	badge_collected = true
	badge_ui.visible = true
	badge_ui.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(badge_ui, "modulate:a", 1.0, 1.0)
	tween.tween_property(badge_ui, "scale", Vector2(1.2, 1.2), 0.3)
	tween.tween_property(badge_ui, "scale", Vector2(1.0, 1.0), 0.2)

	if spark:
		spark.play_happy()

	await get_tree().create_timer(4.0).timeout
	# 可导航到SpellLibrary
	var change_result := get_tree().change_scene_to_file("res://assets/scenes/SpellLibrary.tscn")
	if change_result != OK:
		push_error("[SpiritForestFP] Failed to change to SpellLibrary: %s" % error_string(change_result))

# ——— TreeSpirit 眼睛动画 ———

func _open_tree_eyes() -> void:
	if not tree_spirit_eyes_closed or not tree_spirit_eyes_open:
		return
	tree_spirit_eyes_closed.visible = false
	tree_spirit_eyes_open.visible = true

func _close_tree_eyes() -> void:
	if not tree_spirit_eyes_closed or not tree_spirit_eyes_open:
		return
	tree_spirit_eyes_open.visible = false
	tree_spirit_eyes_closed.visible = true

# ——— TreeSpirit 眼神跟随（在_process中处理） ———

func _process_eye_tracking() -> void:
	if not tree_spirit_eyes_open or not tree_spirit_eyes_open.visible or not tree_spirit.visible:
		return
	var mouse_x: float = get_viewport().get_mouse_position().x
	var screen_center: float = get_viewport().size.x / 2.0
	var offset: float = (mouse_x - screen_center) / screen_center
	var max_offset: float = 8.0

	# 获取瞳孔节点
	var pupil_left: Sprite2D = tree_spirit_eyes_open.get_node_or_null("PupilLeft")
	var pupil_right: Sprite2D = tree_spirit_eyes_open.get_node_or_null("PupilRight")

	if pupil_left:
		pupil_left.position.x = lerpf(pupil_left.position.x, offset * max_offset, 0.1)
	if pupil_right:
		pupil_right.position.x = lerpf(pupil_right.position.x, offset * max_offset, 0.1)

# ——— WateringCan 道具动画 ———

func _show_watering_can() -> void:
	if not watering_can:
		return
	watering_can.visible = true
	# 从屏幕下方飞入到中心位置
	var start_pos: Vector2 = Vector2(960, 1200)
	var end_pos: Vector2 = Vector2(960, 700)
	watering_can.position = start_pos

	var tween: Tween = create_tween()
	tween.tween_property(watering_can, "position", end_pos, 0.8) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _water_flower(flower: Node2D) -> void:
	if not watering_can or not flower:
		return
	# 移动水壶到花朵位置
	var target_pos: Vector2 = flower.global_position + Vector2(0, -50)
	var tween: Tween = create_tween()
	tween.tween_property(watering_can, "global_position", target_pos, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	# 浇水动画（简单闪烁效果）
	if flower.has_method("set_state"):
		flower.set_state("active")

# ——— 相机控制 ———

func _switch_camera_to_tree() -> void:
	if not main_camera:
		return
	var target_pos: Vector2 = Vector2(960, 648)
	var tween: Tween = create_tween()
	tween.tween_property(main_camera, "global_position", target_pos, 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _switch_camera_to_spark() -> void:
	if not main_camera or not spark:
		return
	var target_pos: Vector2 = spark.global_position + Vector2(200, 0)
	var tween: Tween = create_tween()
	tween.tween_property(main_camera, "global_position", target_pos, 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _reset_camera() -> void:
	if not main_camera:
		return
	var tween: Tween = create_tween()
	tween.tween_property(main_camera, "global_position", Vector2(960, 540), 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

# ——— 学习场景控制 ———

func _enter_learning_scene() -> void:
	if not learning_scene:
		return
	learning_scene.visible = true
	_switch_camera_to_learning()

func _exit_learning_scene() -> void:
	if not learning_scene:
		return
	learning_scene.visible = false
	_reset_camera()

func _switch_camera_to_learning() -> void:
	if not main_camera:
		return
	var target_pos: Vector2 = Vector2(400, 600)
	var tween: Tween = create_tween()
	tween.tween_property(main_camera, "global_position", target_pos, 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

# ——— TreeSpirit 对话气泡 ———

func _show_tree_spirit_bubble(text: String) -> void:
	if not tree_spirit:
		return
	_hide_tree_spirit_bubble()
	_tree_bubble = Label.new()
	_tree_bubble.text = text
	_tree_bubble.add_theme_font_size_override("font_size", 20)
	_tree_bubble.add_theme_color_override("font_color", Color.WHITE)
	_tree_bubble.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_tree_bubble.add_theme_constant_override("shadow_offset_x", 2)
	_tree_bubble.add_theme_constant_override("shadow_offset_y", 2)
	_tree_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 显示在 TreeSpirit 上方
	_tree_bubble.position = Vector2(-150, -180)
	tree_spirit.add_child(_tree_bubble)

func _hide_tree_spirit_bubble() -> void:
	if _tree_bubble and is_instance_valid(_tree_bubble):
		_tree_bubble.queue_free()
		_tree_bubble = null

# ——— 工具函数 ———

func _get_flower_by_color(color: String) -> Node2D:
	match color:
		"red": return flower_red
		"blue": return flower_blue
		"yellow": return flower_yellow
	return null

func _show_all_flowers() -> void:
	for flower in [flower_red, flower_blue, flower_yellow]:
		if flower:
			flower.visible = true

func _mark_all_flowers_active() -> void:
	_show_all_flowers()
	activated_colors = REQUIRED_COLORS.duplicate()
	for color in REQUIRED_COLORS:
		var flower := _get_flower_by_color(color)
		if flower and flower.has_method("set_state"):
			flower.set_state("active")

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

func _extract_numbers(text: String) -> Array[int]:
	var numbers: Array[int] = []
	var current: String = ""
	for char in text:
		if char >= "0" and char <= "9":
			current += char
		else:
			if current.length() > 0:
				numbers.append(int(current))
				current = ""
	if current.length() > 0:
		numbers.append(int(current))
	return numbers

func _contains_chinese_number(text: String, target: int) -> bool:
	var chinese: Dictionary = {
		7: ["七", "柒"],
	}
	if chinese.has(target):
		for variant in chinese[target]:
			if text.contains(variant):
				return true
	return false

func _await_tts(timeout: float = 30.0) -> bool:
	var state := {"done": false}
	var cb := func(_duration: float): state["done"] = true
	AudioManager.tts_finished.connect(cb)
	var elapsed := 0.0
	while not state["done"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	AudioManager.tts_finished.disconnect(cb)
	return state["done"]

func _loc(key: String) -> String:
	var is_zh: bool = GameManager.current_lang == "zh"
	var strings: Dictionary = {
		"spark_greeting": {"zh": "欢迎来到精灵森林！我是Spark！", "en": "Welcome to Spirit Forest! I'm Spark!"},
		"tree_greeting": {"zh": "你好，小魔法师！我是TreeSpirit。你叫什么名字？", "en": "Hello, young mage! I'm TreeSpirit. What's your name?"},
		"color_instruction": {"zh": "说出Red、Blue或Yellow来激活魔法花！", "en": "Say Red, Blue, or Yellow to activate the magic flowers!"},
		"color_progress": {"zh": "很好！继续说出剩下的颜色。", "en": "Great! Say the remaining colors."},
		"color_retry": {"zh": "请说 Red、Blue 或 Yellow。", "en": "Please say Red, Blue, or Yellow."},
		"number_instruction": {"zh": "数一数有多少个蘑菇？", "en": "Count how many mushrooms are here!"},
		"number_retry": {"zh": "再试一次，说出你看到的数字。", "en": "Try again and say the number you see."},
		"number_hint": {"zh": "提示：比5多，比10少！", "en": "Hint: More than 5, less than 10!"},
		"quest_name": {"zh": "任务：告诉 TreeSpirit 你的名字", "en": "Quest: Tell TreeSpirit your name"},
		"quest_colors": {"zh": "任务：激活红、蓝、黄三朵魔法花", "en": "Quest: Activate the red, blue, and yellow flowers"},
		"quest_number": {"zh": "任务：数出小溪边的蘑菇", "en": "Quest: Count the mushrooms by the stream"},
		"quest_badge": {"zh": "任务：打开宝箱领取森林徽章", "en": "Quest: Open the chest and claim the Forest Badge"},
		"badge_earned": {"zh": "已获得 Forest Badge！", "en": "Forest Badge earned!"},
	}
	if strings.has(key):
		return strings[key].get("zh" if is_zh else "en", "")
	return ""
