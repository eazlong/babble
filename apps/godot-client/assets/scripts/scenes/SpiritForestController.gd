## 序章场景控制器（原精灵森林改造）
##
## 管理三幕序章流程：
## [1] 小飞猫飞入 + 破冰问候 + 名字收集
## [2] 混沌迷雾世界观揭示 + 玩家接受主线任务
## [3] 蜃影客栈绑定 + 转场长安西市
##
extends Node2D

# ——— 类型引用 ———
const Config = preload("res://assets/scripts/components/scene_config/spirit_forest_config.gd")
const Step = Config.Step

# ——— 状态机 ———
enum NameSubStep { AWAITING_GREETING, AWAITING_NAME }
enum InnSubStep { INTRO, FIRST_GUEST }
var _current_step: Step = Step.SPARK_INTRO_NAME
var _name_sub_step: NameSubStep = NameSubStep.AWAITING_GREETING
var _inn_sub_step: InnSubStep = InnSubStep.INTRO
var _world_reveal_sub_step: int = 0  # 0=intro_mist, 1=curse, 2=quest, 3=accepted

# ——— 尝试计数 ———
var _name_attempts: int = 0
var _quest_attempts: int = 0
var _player_name: String = ""
var _silence_hint_shown: bool = false

# ——— 节点引用 ———
@onready var coach_overlay: CoachOverlay = $CoachLayer/CoachOverlay
@onready var mic_panel: Control = $OverlayLayer/MicPanel
@onready var mic_icon: ColorRect = $OverlayLayer/MicPanel/MicIcon
@onready var mic_label: Label = $OverlayLayer/MicPanel/MicLabel
@onready var spark_npc: Node2D = $SparkNPC
@onready var camera: Camera2D = $Camera2D
@onready var big_tree: Area2D = $EnvironmentObjects/BigTree
var transition_arrow: Control = null
var dialogue_lang_mgr: Node = null

# ——— 隐藏不再使用的节点（原魔法森林资源）———
var oakley_npc: Node2D = null
var magic_flowers: Node2D = null
var watering_can_node: Node2D = null

# ——— 锚点引用 ———
var _spark_shoulders_pos: Vector2 = Config.SPARK_SHOULDER_POS
var _spark_center_pos: Vector2 = Config.SPARK_CENTER_POS

# ——— 语音状态 ———
var voice_listening: bool = false
var mic_tween: Tween = null
var silence_timer: float = 0.0
var record_duration: float = 0.0
var last_player_input: String = ""
var _processing_response: bool = false

# ——— Tween 引用 ———
var _spark_move_tween: Tween = null
var _camera_pan_tween: Tween = null

# ——— 信号 ———
signal step_completed(step: Step)
signal star_earned(amount: int, reason: String)
signal scene_transition_requested(target_scene: String)

# ——— 生命周期 ———

func _ready() -> void:
	_setup_node_visibility()
	_connect_signals()
	_hide_legacy_nodes()
	_init_ambient_vfx()
	_create_mist_particles()

	# 获取任务状态（兼容已有 quest-service）
	HybridAPI.fetch_quest_status("prologue")

	# 延迟启动，等待场景加载
	await get_tree().create_timer(1.0).timeout
	_run_step(_current_step)

func _process(delta: float) -> void:
	if not voice_listening:
		return
	if not VoicePipeline.is_listening:
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
		# 沉默提示：只在 Act 1 打招呼阶段且未显示过提示时触发
		if silence_timer > Config.SILENCE_TIMEOUT and not _silence_hint_shown:
			if _current_step == Step.SPARK_INTRO_NAME and _name_sub_step == NameSubStep.AWAITING_GREETING:
				_silence_hint_shown = true
				var silence_hint: String = _get_text("spark_silence_hint")
				_show_coach_hint(silence_hint, "hint")
				HybridAPI.synthesize_tts(silence_hint, "spirit", "zh")
		if silence_timer > Config.SILENCE_TIMEOUT * 2:
			# 超长沉默，停止监听
			_stop_voice_listening()

func _exit_tree() -> void:
	VFXManager.stop_all_effects()
	_kill_tween(_spark_move_tween)
	_kill_tween(_camera_pan_tween)
	_kill_tween(mic_tween)
	# 移除迷雾粒子
	if has_node("ChaosMistParticles"):
		get_node("ChaosMistParticles").queue_free()

# ——— 初始化 ———

func _setup_node_visibility() -> void:
	# 初始化可选节点引用
	transition_arrow = get_node_or_null("OverlayLayer/TransitionArrow")
	dialogue_lang_mgr = get_node_or_null("DialogueLanguageManager")
	oakley_npc = get_node_or_null("OakleyNPC")
	magic_flowers = get_node_or_null("MagicFlowers")
	watering_can_node = get_node_or_null("WateringCan")

	if mic_panel:
		mic_panel.visible = false

func _hide_legacy_nodes() -> void:
	# 隐藏原魔法森林的 NPC 和道具（序章不再使用）
	if oakley_npc:
		oakley_npc.visible = false
	if magic_flowers:
		magic_flowers.visible = false
	if watering_can_node:
		watering_can_node.visible = false

func _connect_signals() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.quest_status_received.connect(_on_quest_status)
	HybridAPI.quest_report_received.connect(_on_quest_report)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	VoicePipeline.voice_started.connect(_on_voice_started)
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	DialogueManager.player_response_ready.connect(_on_player_response)

func _init_ambient_vfx() -> void:
	var environment_layer: Node = $EnvironmentLayer if has_node("EnvironmentLayer") else null
	if environment_layer:
		VFXManager.play_ambient_float(environment_layer, 8)

## 创建混沌迷雾粒子特效（序章专用）
func _create_mist_particles() -> void:
	var mist := GPUParticles2D.new()
	mist.name = "ChaosMistParticles"
	mist.amount = 30
	mist.lifetime = 6.0
	mist.emitting = true

	# 粒子材质（使用内置圆形渐变纹理）
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.1, 0.02, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, -1, 0)
	mat.damping_min = 2.0
	mat.damping_max = 5.0
	mat.angular_velocity_min = -20.0
	mat.angular_velocity_max = 20.0
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	mat.color = Color(0.6, 0.6, 0.7, 0.15)  # 淡灰紫色迷雾
	mist.process_material = mat

	# 绘制纹理（使用 1x1 白色纹理作为基础）
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var tex := ImageTexture.create_from_image(img)
	mist.texture = tex

	# 迷雾覆盖整个屏幕
	mist.position = Vector2(0, 360)
	mist.visibility_rect = Rect2(-2000, -800, 4000, 1600)

	# 添加到场景
	add_child(mist)

# ——— 状态机核心 ———

func _run_step(step: Step) -> void:
	_current_step = step
	match step:
		Step.SPARK_INTRO_NAME:
			_step_1_spark_intro_name()
		Step.WORLD_REVEAL:
			_step_2_world_reveal()
		Step.INN_BINDING_EXIT:
			_step_3_inn_binding_exit()

func _advance_step() -> void:
	var next_step: int = (_current_step as int) + 1
	step_completed.emit(_current_step)
	if next_step <= Step.INN_BINDING_EXIT:
		_run_step(next_step as Step)
	else:
		print("[Prologue] All steps completed!")

func _get_current_lang() -> String:
	return GameManager.current_lang

func _get_text(key: String) -> String:
	return Config.get_dialogue(key, _get_current_lang())

# ——— Act 1: 破冰与相识 ———

func _step_1_spark_intro_name() -> void:
	_name_sub_step = NameSubStep.AWAITING_GREETING

	# 1a: 小飞猫从远处飞入到肩膀位置
	await _move_spark_to(Config.SPARK_OFFSCREEN_POS, 0.0)
	spark_npc.visible = true
	await _move_spark_to(_spark_shoulders_pos, Config.SPARK_FLY_IN_DURATION)

	# 1b: 小飞猫 "Hello! Can you hear me?"
	var greeting: String = _get_text("spark_greeting")
	_show_coach_hint(greeting, "speaking")
	HybridAPI.synthesize_tts(greeting, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.5).timeout

	# 1c: 等待玩家回应打招呼
	_start_voice_listening()
	# 沉默提示由 _process() 中的 silence_timer 统一处理

func _on_greeting_received(player_text: String) -> void:
	# 玩家已打招呼，确认并进入名字阶段
	_stop_voice_listening()

	# 1d: 小飞猫欢迎 + 自我介绍 + 问名字
	var welcome_text: String = _get_text("spark_ask_name")
	_show_coach_hint(welcome_text, "speaking")
	HybridAPI.synthesize_tts(welcome_text, "spirit", _get_current_lang())
	await _await_tts()

	# 1e: 切换到名字阶段，等待玩家说名字
	_name_sub_step = NameSubStep.AWAITING_NAME
	_start_voice_listening()

func _on_player_name_given(player_name_text: String) -> void:
	_player_name = player_name_text
	GameManager.set_player_info(player_name_text, 8)
	_stop_voice_listening()

	# 1f: 小飞猫庆祝
	var celebrate_text: String = _get_text("spark_name_celebrate") % player_name_text
	_show_coach_hint(celebrate_text, "happy")
	HybridAPI.synthesize_tts(celebrate_text, "spirit", _get_current_lang())
	await _await_tts()

	# 1g: 星星奖励
	_emit_star(Config.STAR_NAME_COLLECTION, "name_collection")
	var scores: Dictionary = await HybridAPI.assess_player_input(
		player_name_text, "name_collection", "prologue"
	)
	HybridAPI.report_quest_complete("name_collection", "prologue", scores, player_name_text)

	await get_tree().create_timer(1.0).timeout
	_advance_step()

# ——— Act 2: 世界观揭示 ———

func _step_2_world_reveal() -> void:
	_world_reveal_sub_step = 0

	# 2a: 小飞猫飞到屏幕中央，开始讲述
	await _move_spark_to(_spark_center_pos, 0.5)

	# 2b: 讲解迷雾起源
	var mist_text: String = _get_text("world_intro_mist")
	_show_coach_hint(mist_text, "speaking")
	HybridAPI.synthesize_tts(mist_text, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.8).timeout

	# 2c: 讲解诅咒效果
	var curse_text: String = _get_text("world_intro_curse")
	_show_coach_hint(curse_text, "speaking")
	HybridAPI.synthesize_tts(curse_text, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.8).timeout

	# 2d: 赋予使命
	var quest_text: String = _get_text("world_intro_quest")
	_show_coach_hint(quest_text, "speaking")
	HybridAPI.synthesize_tts(quest_text, "spirit", _get_current_lang())
	await _await_tts()

	# 2e: 等待玩家接受任务
	_world_reveal_sub_step = 3
	var accept_hint: String = _get_text("spark_quest_accept_hint")
	_show_coach_hint(accept_hint, "hint")
	_start_voice_listening()

func _on_quest_acceptance(text: String) -> void:
	_stop_voice_listening()

	# 检查是否包含肯定回应
	var normalized := text.to_lower().strip_edges()
	var accepted := normalized.contains("yes") or normalized.contains("will") or normalized.contains("can")

	if accepted or text.length() > 3:  # 宽松判定：有内容即视为接受
		# 2f: 小飞猫庆祝
		var accepted_text: String = _get_text("spark_quest_accepted")
		_show_coach_hint(accepted_text, "happy")
		HybridAPI.synthesize_tts(accepted_text, "spirit", _get_current_lang())
		await _await_tts()

		# 2g: 星星奖励
		_emit_star(Config.STAR_ACCEPT_QUEST, "quest_acceptance")
		var scores: Dictionary = await HybridAPI.assess_player_input(
			text, "quest_acceptance", "prologue"
		)
		HybridAPI.report_quest_complete("quest_acceptance", "prologue", scores, text)

		await get_tree().create_timer(1.0).timeout
		_advance_step()
	else:
		# 重试
		_quest_attempts += 1
		if _quest_attempts >= Config.MAX_ATTEMPTS:
			# 强制推进
			_advance_step()
		else:
			var retry_hint: String = _get_text("spark_quest_accept_hint")
			_show_coach_hint(retry_hint, "hint")
			_start_voice_listening()

# ——— Act 3: 客栈绑定 + 转场 ———

func _step_3_inn_binding_exit() -> void:
	_inn_sub_step = InnSubStep.INTRO

	# 3a: 小飞猫介绍蜃影客栈
	var inn_text: String = _get_text("inn_intro")
	_show_coach_hint(inn_text, "speaking")
	HybridAPI.synthesize_tts(inn_text, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.5).timeout

	# 3b: 客栈历史
	var history_text: String = _get_text("inn_intro_history")
	_show_coach_hint(history_text, "speaking")
	HybridAPI.synthesize_tts(history_text, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.5).timeout

	# 3c: 机制预告
	var mechanic_text: String = _get_text("inn_mechanic_intro")
	_show_coach_hint(mechanic_text, "speaking")
	HybridAPI.synthesize_tts(mechanic_text, "spirit", _get_current_lang())
	await _await_tts()
	await get_tree().create_timer(0.5).timeout

	# 3c2: 首位客人到达 — 经营教学
	var first_guest_text: String = _get_text("inn_first_guest")
	_show_coach_hint(first_guest_text, "speaking")
	HybridAPI.synthesize_tts(first_guest_text, "spirit", _get_current_lang())
	await _await_tts()

	# 等待玩家用 "Hello" 招呼首位客人
	_inn_sub_step = InnSubStep.FIRST_GUEST
	_start_voice_listening()

func _on_first_guest_greeted(player_text: String) -> void:
	_stop_voice_listening()

	# 简化判定：包含 "hello" 或 "hi" 即视为成功
	var normalized: String = player_text.to_lower().strip_edges()
	if normalized.contains("hello") or normalized.contains("hi") or player_text.length() > 0:
		# 成功招呼客人
		var success_text: String = "Great job! The merchant is happy." if _get_current_lang() == "en" else "做得好！商人很开心。"
		_show_coach_hint(success_text, "happy")
		HybridAPI.synthesize_tts(success_text, "spirit", _get_current_lang())
		await _await_tts()
	else:
		# 鼓励再试
		var retry_text: String = "Try saying 'Hello' to welcome him!" if _get_current_lang() == "en" else "试着对他说 'Hello' 来欢迎他！"
		_show_coach_hint(retry_text, "hint")
		HybridAPI.synthesize_tts(retry_text, "spirit", _get_current_lang())
		await _await_tts()
		_start_voice_listening()
		return

	await get_tree().create_timer(1.0).timeout

	# 3d: 转场提示
	var transition_text: String = _get_text("inn_transition")
	_show_coach_hint(transition_text, "happy")
	HybridAPI.synthesize_tts(transition_text, "spirit", _get_current_lang())
	await _await_tts()

	# 3e: 箭头出现 → 等待玩家点击转场
	await get_tree().create_timer(1.0).timeout
	if transition_arrow:
		transition_arrow.visible = true
		_start_arrow_pulse()
	else:
		await get_tree().create_timer(2.0).timeout
		_transition_to_next_scene()

func _on_transition_arrow_pressed() -> void:
	_stop_arrow_pulse()
	_transition_to_next_scene()

func _transition_to_next_scene() -> void:
	# 解锁长安西市（暂用占位路径）
	if not GameManager.unlocked_areas.has("ChangAnMarket"):
		GameManager.unlocked_areas.append("ChangAnMarket")
	GameManager.lxp_score += Config.TOTAL_STARS * 10
	GameManager.save_progress()

	# 淡出转场
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, Config.SCENE_FADE_DURATION)
	fade_tween.tween_callback(func():
		scene_transition_requested.emit(Config.TARGET_SCENE_PATH)
		get_tree().change_scene_to_file(Config.TARGET_SCENE_PATH)
	)

# ——— 系统集成辅助方法 ———

func _move_spark_to(target_pos: Vector2, duration: float = 0.8) -> void:
	if not spark_npc:
		return
	_kill_tween(_spark_move_tween)
	_spark_move_tween = create_tween()
	if duration <= 0.0:
		spark_npc.position = target_pos
		return
	_spark_move_tween.tween_property(spark_npc, "position", target_pos, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	UITweenManager.register_tween("spark_move", _spark_move_tween)
	await _spark_move_tween.finished

func _pan_camera_to(target_x: float, duration: float = 0.8) -> void:
	if not camera:
		return
	_kill_tween(_camera_pan_tween)
	_camera_pan_tween = create_tween()
	_camera_pan_tween.tween_property(camera, "position:x", target_x, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	UITweenManager.register_tween("camera_pan", _camera_pan_tween)
	await _camera_pan_tween.finished

func _show_coach_hint(text: String, emotion: String = "hint") -> void:
	if coach_overlay:
		coach_overlay.show_hint(text, emotion)

func _emit_star(amount: int, reason: String) -> void:
	star_earned.emit(amount, reason)
	print("[Prologue] Star earned: +%d (%s)" % [amount, reason])

func _kill_tween(tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()

# ——— 语音流程 ———

func _start_voice_listening() -> void:
	if voice_listening:
		return
	if DialogueManager.dialogue_state != "idle":
		DialogueManager.end_dialogue()
	voice_listening = true
	VoicePipeline.start_listening()
	silence_timer = 0.0
	record_duration = 0.0
	_silence_hint_shown = false
	_show_mic_panel()

func _stop_voice_listening() -> void:
	if not voice_listening:
		return
	voice_listening = false
	VoicePipeline.stop_listening()
	_hide_mic_panel()
	silence_timer = 0.0
	record_duration = 0.0

func _show_mic_panel() -> void:
	if not mic_panel:
		return
	mic_panel.visible = true
	mic_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(mic_panel, "modulate:a", 1.0, 0.3)
	UITweenManager.register_tween("ui_feedback", tween)
	_start_mic_pulse()

func _hide_mic_panel() -> void:
	_stop_mic_pulse()
	if not mic_panel:
		return
	var tween := create_tween()
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

func _stop_mic_pulse() -> void:
	_kill_tween(mic_tween)
	mic_tween = null

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

# ——— 信号回调 ———

func _on_voice_started() -> void:
	print("[Prologue] _on_voice_started")
	_show_mic_panel()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[Prologue] _on_voice_ended triggered!")
	if not voice_listening:
		return
	_stop_voice_listening()

	if coach_overlay:
		coach_overlay.show_hint("识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_asr_received(result: Dictionary) -> void:
	print("[Prologue] ASR result: ", result)
	var text: String = result.get("text", "")
	if text.is_empty():
		print("[Prologue] ASR text empty")
		if voice_listening or _is_awaiting_voice_input():
			_start_voice_listening()
		return
	if _processing_response:
		print("[Prologue] _on_asr_received ignored: already processing")
		return
	_on_player_response(text)

func _on_player_response(text: String) -> void:
	if _processing_response:
		print("[Prologue] _on_player_response ignored: already processing")
		return
	_processing_response = true
	last_player_input = text
	match _current_step:
		Step.SPARK_INTRO_NAME:
			if _name_sub_step == NameSubStep.AWAITING_GREETING:
				await _on_greeting_received(text)
			else:
				await _on_player_name_given(text)
		Step.WORLD_REVEAL:
			await _on_quest_acceptance(text)
		Step.INN_BINDING_EXIT:
			if _inn_sub_step == InnSubStep.FIRST_GUEST:
				await _on_first_guest_greeted(text)
		_:
			pass
	_processing_response = false

func _is_awaiting_voice_input() -> bool:
	return _current_step in [
		Step.SPARK_INTRO_NAME,
		Step.WORLD_REVEAL,
	]

func _on_dialogue_started(npc_id: String) -> void:
	print("[Prologue] Dialogue started with: ", npc_id)

func _on_dialogue_ended() -> void:
	print("[Prologue] Dialogue ended")

func _on_quest_status(result: Dictionary) -> void:
	print("[Prologue] Quest status: ", result)

func _on_quest_report(result: Dictionary) -> void:
	print("[Prologue] Quest report result: ", result)
	if result.get("success", false):
		var lxp_earned: int = result.get("lxp_earned", 0)
		if lxp_earned > 0:
			GameManager.lxp_score += lxp_earned

# ——— DialogueLanguageManager 回调（暂不需要，序章不使用 DialogueManager） ———

var _arrow_pulse_tween: Tween

func _start_arrow_pulse() -> void:
	if not transition_arrow:
		return
	_kill_tween(_arrow_pulse_tween)
	_arrow_pulse_tween = create_tween()
	_arrow_pulse_tween.set_loops()
	_arrow_pulse_tween.tween_property(transition_arrow, "modulate:a", 0.5, 0.6)
	_arrow_pulse_tween.tween_property(transition_arrow, "modulate:a", 1.0, 0.6)

func _stop_arrow_pulse() -> void:
	_kill_tween(_arrow_pulse_tween)
	if transition_arrow:
		transition_arrow.modulate.a = 1.0
