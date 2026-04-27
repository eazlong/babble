# Godot 轨道 Phase 2 实施计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 创建 Godot 4.3 并行开发轨道，实现语音交互管线 + 基础对话系统，用于技术评估对比。

**Architecture:** Godot 4.3 LTS + GDScript，Autoload 全局单例模式，HTTP API 调用云端服务（ASR/LLM/TTS），VAD 自动语音检测。

**Tech Stack:** Godot 4.3, GDScript, HTTPRequest, AudioStreamPlayer, CharacterBody2D

---

## Week 1: 项目搭建 + MainMenu 场景

### Task 1: 创建 Godot 项目骨架

**Files:**
- Create: `apps/godot-client/project.godot`
- Create: `apps/godot-client/.gitignore`

**Step 1: 创建项目目录**

```bash
mkdir -p apps/godot-client/assets/{scenes,scripts/{autoload,components,utils},resources/{sprites,audio,fonts},addons}
```

**Step 2: 创建 project.godot 配置文件**

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are mostly internal.

config_version=5

[application]

config/name="LinguaQuest RPG"
run/main_scene="res://assets/scenes/MainMenu.tscn"
config/features=PackedStringArray("4.3", "Forward Plus")
config/icon="res://icon.svg"

[autoload]

GameManager="*res://assets/scripts/autoload/GameManager.gd"
HybridAPI="*res://assets/scripts/autoload/HybridAPI.gd"
VoicePipeline="*res://assets/scripts/autoload/VoicePipeline.gd"
DialogueManager="*res://assets/scripts/autoload/DialogueManager.gd"
AudioManager="*res://assets/scripts/autoload/AudioManager.gd"

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"

[rendering]

renderer/rendering_method="mobile"

**Step 3: 创建 .gitignore**

```gitignore
# Godot-specific ignores
.import/
*.import
export.cfg
export_presets.cfg

# Imported assets
*.translated
*.translation

# Godot 4 specific
.godot/

# OS specific
.DS_Store
Thumbs.db

# IDE
*.swp
*.swo
.idea/
.vscode/
```

**Step 4: 验证项目结构**

Run: `ls -la apps/godot-client/`
Expected: 目录结构正确，project.godot 存在

**Step 5: Commit**

```bash
git add apps/godot-client/
git commit -m "feat: create Godot 4.3 project skeleton for parallel track"
```

---

### Task 2: GameManager 全局单例

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/GameManager.gd`

**Step 1: 创建 GameManager.gd**

```gdscript
extends Node

# 玩家数据
var player_name: String = ""
var player_age: int = 0
var current_lang: String = "zh"
var current_scene: String = "MainMenu"

# 游戏进度
var unlocked_areas: Array[String] = ["SpiritForest"]
var completed_dialogues: Array[String] = []
var vocabulary_learned: Array[String] = []

# 语言经验值
var lxp_score: int = 0

# 信号
signal language_changed(lang: String)
signal player_info_updated(name: String, age: int)
signal progress_saved()

func _ready() -> void:
	load_progress()

func set_player_info(name: String, age: int) -> void:
	player_name = name
	player_age = age
	player_info_updated.emit(name, age)
	save_progress()

func set_language(lang: String) -> void:
	current_lang = lang
	language_changed.emit(lang)
	save_progress()

func save_progress() -> void:
	var save_data = {
		"player_name": player_name,
		"player_age": player_age,
		"current_lang": current_lang,
		"unlocked_areas": unlocked_areas,
		"lxp_score": lxp_score,
		"completed_dialogues": completed_dialogues
	}
	
	var file = FileAccess.open("user://save.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
		progress_saved.emit()

func load_progress() -> bool:
	if FileAccess.file_exists("user://save.json"):
		var file = FileAccess.open("user://save.json", FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var data = JSON.parse_string(json_string)
			if data:
				player_name = data.get("player_name", "")
				player_age = data.get("player_age", 0)
				current_lang = data.get("current_lang", "zh")
				unlocked_areas = data.get("unlocked_areas", ["SpiritForest"])
				lxp_score = data.get("lxp_score", 0)
				completed_dialogues = data.get("completed_dialogues", [])
				return true
	return false

func reset() -> void:
	player_name = ""
	player_age = 0
	lxp_score = 0
	unlocked_areas = ["SpiritForest"]
	completed_dialogues.clear()
	vocabulary_learned.clear()
	save_progress()
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/GameManager.gd
git commit -m "feat: add GameManager autoload singleton for global state"
```

---

### Task 3: AudioManager 全局单例

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/AudioManager.gd`

**Step 1: 创建 AudioManager.gd**

```gdscript
extends Node

var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var tts_player: AudioStreamPlayer

var bgm_volume: float = 0.8
var sfx_volume: float = 1.0
var tts_volume: float = 1.0

signal tts_finished()

func _ready() -> void:
	bgm_player = AudioStreamPlayer.new()
	sfx_player = AudioStreamPlayer.new()
	tts_player = AudioStreamPlayer.new()
	
	add_child(bgm_player)
	add_child(sfx_player)
	add_child(tts_player)
	
	bgm_player.volume_db = linear_to_db(bgm_volume)
	sfx_player.volume_db = linear_to_db(sfx_volume)
	tts_player.volume_db = linear_to_db(tts_volume)
	
	tts_player.finished.connect(_on_tts_finished)

func play_bgm(stream: AudioStream) -> void:
	if bgm_player.stream != stream:
		bgm_player.stream = stream
		bgm_player.play()

func stop_bgm() -> void:
	bgm_player.stop()

func play_sfx(stream: AudioStream) -> void:
	sfx_player.stream = stream
	sfx_player.play()

func play_tts(stream: AudioStream) -> void:
	tts_player.stream = stream
	tts_player.play()

func _on_tts_finished() -> void:
	tts_finished.emit()

func play_audio_from_base64(base64_data: String, format: String = "wav") -> void:
	var bytes = Marshalls.base64_to_raw(base64_data)
	var stream: AudioStream
	
	if format == "wav":
		stream = AudioStreamWAV.new()
		# Note: 需要根据实际音频格式设置参数
	elif format == "ogg":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)
	
	if stream:
		play_tts(stream)

func set_bgm_volume(volume: float) -> void:
	bgm_volume = volume
	bgm_player.volume_db = linear_to_db(volume)

func set_sfx_volume(volume: float) -> void:
	sfx_volume = volume
	sfx_player.volume_db = linear_to_db(volume)

func set_tts_volume(volume: float) -> void:
	tts_volume = volume
	tts_player.volume_db = linear_to_db(volume)
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/AudioManager.gd
git commit -m "feat: add AudioManager for BGM/SFX/TTS playback"
```

---

### Task 4: HybridAPI 云端接口封装

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/HybridAPI.gd`

**Step 1: 创建 HybridAPI.gd**

```gdscript
extends Node

const API_BASE_URL = "http://localhost:3000/api"  # 开发环境，生产环境需替换

var http_request: HTTPRequest

signal services_ready()
signal tts_received(result: Dictionary)
signal asr_received(result: Dictionary)
signal dialogue_received(result: Dictionary)
signal api_error(error: String)

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# 检测服务状态
func ping_services() -> void:
	var error = http_request.request(API_BASE_URL + "/ping", HTTPClient.METHOD_GET)
	if error != OK:
		api_error.emit("Failed to ping services: " + str(error))

# TTS 合成
func synthesize_tts(text: String, voice_id: String = "spirit", lang: String = "zh") -> void:
	var body = JSON.stringify({
		"text": text,
		"voice_id": voice_id,
		"lang": lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/tts/synthesize", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("TTS request failed: " + str(error))
		return
	await http_request.request_completed
	# 结果在 _on_request_completed 中处理

# ASR 识别
func recognize_speech(audio_data: PackedByteArray, lang: String = "zh") -> void:
	var body = JSON.stringify({
		"audio_data": Marshalls.raw_to_base64(audio_data),
		"lang": lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/asr/recognize", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("ASR request failed: " + str(error))
		return
	await http_request.request_completed

# 对话生成
func send_dialogue(user_text: String, npc_id: String, context: Array = []) -> void:
	var body = JSON.stringify({
		"user_text": user_text,
		"npc_id": npc_id,
		"context": context,
		"lang": GameManager.current_lang
	})
	var headers = ["Content-Type: application/json"]
	var error = http_request.request(API_BASE_URL + "/dialogue/generate", HTTPClient.METHOD_POST, headers, body)
	if error != OK:
		api_error.emit("Dialogue request failed: " + str(error))
		return
	await http_request.request_completed

# 完整语音对话流程
func process_voice_dialogue(audio_data: PackedByteArray, npc_id: String, lang: String = "zh") -> Dictionary:
	# 1. ASR
	recognize_speech(audio_data, lang)
	var asr_result = await asr_received
	
	if asr_result.has("error"):
		return {"error": asr_result.error}
	
	var user_text = asr_result.get("text", "")
	
	# 2. LLM 对话
	send_dialogue(user_text, npc_id, DialogueManager.dialogue_history)
	var dialogue_result = await dialogue_received
	
	if dialogue_result.has("error"):
		return {"error": dialogue_result.error}
	
	var npc_response = dialogue_result.get("response", "")
	
	# 3. TTS
	synthesize_tts(npc_response, npc_id, lang)
	var tts_result = await tts_received
	
	return {
		"user_text": user_text,
		"npc_response": npc_response,
		"audio_data": tts_result.get("audio_data", "")
	}

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		api_error.emit("HTTP request failed with result: " + str(result))
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null:
		api_error.emit("Failed to parse JSON response")
		return
	
	# 根据请求类型分发信号（需要追踪当前请求类型）
	if json.has("audio_data"):
		tts_received.emit(json)
	elif json.has("text"):
		asr_received.emit(json)
	elif json.has("response"):
		dialogue_received.emit(json)
	else:
		services_ready.emit()
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/HybridAPI.gd
git commit -m "feat: add HybridAPI for cloud service integration"
```

---

### Task 5: VoicePipeline 语音检测与录制

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/VoicePipeline.gd`

**Step 1: 创建 VoicePipeline.gd**

```gdscript
extends Node

var is_recording: bool = false
var is_listening: bool = false
var audio_buffer: PackedByteArray = PackedByteArray()

var recording_stream: AudioStreamWAV
var audio_capture: AudioEffectCapture

var silence_threshold: float = 0.02  # 静音阈值
var silence_duration: float = 1.5    # 静音持续时间（秒）
var last_voice_time: float = 0.0

signal voice_started()
signal voice_ended(audio_data: PackedByteArray)
signal listening_started()
signal listening_stopped()

func _ready() -> void:
	# 初始化音频录制
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx == -1:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, "Record")
	
	audio_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus_idx, audio_capture)

func start_listening() -> void:
	is_listening = true
	audio_buffer.clear()
	listening_started.emit()
	
	# 开始捕获音频
	audio_capture.clear_buffer()

func stop_listening() -> void:
	is_listening = false
	is_recording = false
	listening_stopped.emit()

func _process(delta: float) -> void:
	if not is_listening:
		return
	
	# 获取音频帧
	var frames = audio_capture.get_buffer(audio_capture.get_frames_available())
	
	if frames.size() > 0:
		# 检测音量
		var volume = calculate_volume(frames)
		
		if volume > silence_threshold:
			# 有声音
			if not is_recording:
				is_recording = true
				voice_started.emit()
			
			last_voice_time = Time.get_ticks_msec() / 1000.0
			audio_buffer.append_array(frames.to_byte_array())
		
		elif is_recording:
			# 检查静音持续时间
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_voice_time > silence_duration:
				# 静音足够长，结束录制
				is_recording = false
				var final_audio = audio_buffer.duplicate()
				audio_buffer.clear()
				voice_ended.emit(final_audio)

func calculate_volume(frames: PackedVector2Array) -> float:
	var sum: float = 0.0
	for frame in frames:
		sum += abs(frame.x) + abs(frame.y)
	return sum / (frames.size() * 2.0)
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/VoicePipeline.gd
git commit -m "feat: add VoicePipeline with VAD auto-detection"
```

---

### Task 6: DialogueManager 对话流程编排

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd`

**Step 1: 创建 DialogueManager.gd**

```gdscript
extends Node

var current_npc_id: String = ""
var dialogue_history: Array[Dictionary] = []
var dialogue_state: String = "idle"  # idle, active, waiting_response

signal dialogue_started(npc_id: String)
signal dialogue_ended()
signal player_response_ready(text: String)
signal npc_response_ready(response: String)

func _ready() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.dialogue_received.connect(_on_dialogue_received)
	HybridAPI.tts_received.connect(_on_tts_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)

func start_npc_dialogue(npc_id: String, greeting: String) -> void:
	current_npc_id = npc_id
	dialogue_history.clear()
	dialogue_state = "active"
	
	dialogue_started.emit(npc_id)
	
	# 显示问候语 + TTS
	DialogueBox.show_message(npc_id, greeting)
	
	# 调用 TTS
	HybridAPI.synthesize_tts(greeting, npc_id, GameManager.current_lang)
	await HybridAPI.tts_received
	
	# TTS 播放完毕后开启语音监听
	await AudioManager.tts_finished
	VoicePipeline.start_listening()
	DialogueBox.show_voice_listening()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if dialogue_state != "active":
		return
	
	dialogue_state = "waiting_response"
	DialogueBox.hide_voice_listening()
	
	# 发送完整语音对话流程
	var result = await HybridAPI.process_voice_dialogue(audio_data, current_npc_id, GameManager.current_lang)
	
	if result.has("error"):
		DialogueBox.show_message(current_npc_id, "抱歉，我没听清楚，请再说一次。")
		VoicePipeline.start_listening()
		dialogue_state = "active"
		return
	
	# 显示玩家识别文字
	player_response_ready.emit(result.user_text)
	
	# 显示 NPC 回复
	DialogueBox.show_message(current_npc_id, result.npc_response)
	npc_response_ready.emit(result.npc_response)
	
	# 播放 TTS
	if result.audio_data:
		AudioManager.play_audio_from_base64(result.audio_data)
	
	await AudioManager.tts_finished
	
	# 继监听或结束对话
	dialogue_state = "active"
	VoicePipeline.start_listening()
	DialogueBox.show_voice_listening()

func _on_asr_received(result: Dictionary) -> void:
	pass  # 处理在 process_voice_dialogue 中完成

func _on_dialogue_received(result: Dictionary) -> void:
	pass  # 处理在 process_voice_dialogue 中完成

func _on_tts_received(result: Dictionary) -> void:
	pass  # 处理在 process_voice_dialogue 中完成

func end_dialogue() -> void:
	dialogue_state = "idle"
	VoicePipeline.stop_listening()
	DialogueBox.hide_message()
	dialogue_ended.emit()
	
	# 记录完成
	GameManager.completed_dialogues.append(current_npc_id)
	GameManager.save_progress()
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/DialogueManager.gd
git commit -m "feat: add DialogueManager for voice dialogue orchestration"
```

---

## Week 2: 场景 + UI 组件

### Task 7: DialogueBox UI 组件

**Files:**
- Create: `apps/godot-client/assets/scripts/components/DialogueBox.gd`

**Step 1: 创建 DialogueBox.gd**

```gdscript
extends CanvasLayer

@onready var dialogue_panel: Panel = $DialoguePanel
@onready var npc_name_label: Label = $DialoguePanel/NPCNameLabel
@onready var dialogue_text: RichTextLabel = $DialoguePanel/DialogueText
@onready var voice_indicator: Control = $DialoguePanel/VoiceIndicator

var is_visible: bool = false

func _ready() -> void:
	hide_message()

func show_message(npc_name: String, text: String) -> void:
	npc_name_label.text = npc_name
	dialogue_text.text = text
	
	if not is_visible:
		is_visible = true
		dialogue_panel.modulate.a = 0
		dialogue_panel.visible = true
		
		var tween = create_tween()
		tween.tween_property(dialogue_panel, "modulate:a", 1.0, 0.3)

func hide_message() -> void:
	if is_visible:
		var tween = create_tween()
		tween.tween_property(dialogue_panel, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func():
			dialogue_panel.visible = false
			is_visible = false
		)

func show_voice_listening() -> void:
	voice_indicator.visible = true
	# 脉冲动画
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(voice_indicator, "modulate:a", 0.5, 0.5)
	tween.tween_property(voice_indicator, "modulate:a", 1.0, 0.5)

func hide_voice_listening() -> void:
	voice_indicator.visible = false
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/components/DialogueBox.gd
git commit -m "feat: add DialogueBox UI component with fade animations"
```

---

### Task 8: CoachOverlay 精灵教练 UI

**Files:**
- Create: `apps/godot-client/assets/scripts/components/CoachOverlay.gd`

**Step 1: 创建 CoachOverlay.gd**

```gdscript
extends Control

@onready var coach_sprite: AnimatedSprite2D = $CoachSprite
@onready var dialogue_bubble: Panel = $DialogueBubble
@onready var dialogue_text: RichTextLabel = $DialogueBubble/DialogueText

@export var fly_duration: float = 4.0

signal fly_in_completed()
signal hint_shown()

func fly_in_from(start_pos: Vector2, end_pos: Vector2, duration: float = fly_duration, callback: Callable = Callable()) -> void:
	coach_sprite.position = start_pos
	coach_sprite.visible = true
	
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(coach_sprite, "position", end_pos, duration)
	
	if callback.is_valid():
		tween.tween_callback(callback)
	else:
		tween.tween_callback(func(): fly_in_completed.emit())

func show_hint(text: String, emotion: String = "neutral") -> void:
	dialogue_text.text = text
	dialogue_bubble.visible = true
	dialogue_bubble.modulate.a = 0
	
	var tween = create_tween()
	tween.tween_property(dialogue_bubble, "modulate:a", 1.0, 0.3)
	
	# 根据 emotion 播放精灵动画
	coach_sprite.play(emotion)  # neutral, happy, surprised, curious
	
	hint_shown.emit()

func hide_hint() -> void:
	var tween = create_tween()
	tween.tween_property(dialogue_bubble, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): dialogue_bubble.visible = false)

func set_emotion(emotion: String) -> void:
	coach_sprite.play(emotion)
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/components/CoachOverlay.gd
git commit -m "feat: add CoachOverlay with fly-in animation"
```

---

### Task 9: MainMenuController 主菜单控制器

**Files:**
- Create: `apps/godot-client/assets/scripts/components/MainMenuController.gd`

**Step 1: 创建 MainMenuController.gd**

```gdscript
extends Node2D

@onready var coach_overlay: CoachOverlay = $CoachOverlay
@onready var lang_panel: Control = $LangPanel
@onready var lang_zh_button: Button = $LangPanel/LangZhButton
@onready var lang_en_button: Button = $LangPanel/LangEnButton

var selected_lang: String = "zh"

func _ready() -> void:
	# 隐藏语言面板，等待精灵飞入
	lang_panel.visible = false
	lang_panel.modulate.a = 0
	
	# 检查服务状态
	HybridAPI.ping_services()
	
	# 精灵从右侧飞入
	coach_overlay.fly_in_from(Vector2(800, 300), Vector2(540, 300), 4.0, _on_fly_in_completed)

func _on_fly_in_completed() -> void:
	# 显示欢迎语
	var welcome_text = "你好！准备好学习魔法英语了吗？选择你的语言吧！"
	if GameManager.current_lang == "en":
		welcome_text = "Hello! Ready to learn magic English? Pick your language!"
	
	coach_overlay.show_hint(welcome_text, "happy")
	
	# TTS 播放
	HybridAPI.synthesize_tts(welcome_text, "spirit", GameManager.current_lang)
	
	# 显示语言选择面板
	show_language_panel()

func show_language_panel() -> void:
	lang_panel.visible = true
	
	# 按钮滑入动画
	lang_zh_button.position = Vector2(-300, 100)
	lang_en_button.position = Vector2(300, 100)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(lang_zh_button, "position", Vector2(100, 100), 0.5)
	tween.tween_property(lang_en_button, "position", Vector2(440, 100), 0.5)
	
	tween.chain()
	tween.tween_property(lang_panel, "modulate:a", 1.0, 0.3)

func _on_lang_zh_button_pressed() -> void:
	selected_lang = "zh"
	GameManager.set_language("zh")
	
	var confirm_text = "好的！中文模式！出发吧！"
	coach_overlay.show_hint(confirm_text, "happy")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "zh")
	
	await AudioManager.tts_finished
	enter_game_scene()

func _on_lang_en_button_pressed() -> void:
	selected_lang = "en"
	GameManager.set_language("en")
	
	var confirm_text = "Great! English mode! Let's go!"
	coach_overlay.show_hint(confirm_text, "happy")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "en")
	
	await AudioManager.tts_finished
	enter_game_scene()

func enter_game_scene() -> void:
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://assets/scenes/SpiritForest.tscn")
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/components/MainMenuController.gd
git commit -m "feat: add MainMenuController with coach fly-in and language selection"
```

---

### Task 10: PlayerController 玩家控制器

**Files:**
- Create: `apps/godot-client/assets/scripts/components/PlayerController.gd`

**Step 1: 创建 PlayerController.gd**

```gdscript
extends CharacterBody2D

@export var speed: float = 200.0
@export var acceleration: float = 1500.0
@export var friction: float = 800.0

@onready var sprite: AnimatedSprite2D = $Sprite

var input_direction: Vector2 = Vector2.ZERO

func _physics_process(delta: float) -> void:
	# 获取输入
	input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	
	# 计算速度
	if input_direction != Vector2.ZERO:
		velocity = velocity.move_toward(input_direction * speed, acceleration * delta)
		sprite.play("walk")
		
		# 根据方向翻转精灵
		if input_direction.x < 0:
			sprite.flip_h = true
		elif input_direction.x > 0:
			sprite.flip_h = false
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		sprite.play("idle")
	
	move_and_slide()

func get_position() -> Vector2:
	return global_position
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/components/PlayerController.gd
git commit -m "feat: add PlayerController with movement and animation"
```

---

### Task 11: NPCController NPC 控制器

**Files:**
- Create: `apps/godot-client/assets/scripts/components/NPCController.gd`

**Step 1: 创建 NPCController.gd**

```gdscript
extends StaticBody2D

@export var npc_id: String = "spark"
@export var npc_name_zh: String = "精灵教练 Spark"
@export var npc_name_en: String = "Spirit Coach Spark"
@export var greeting_zh: String = "你好！我是 Spark，你的语言学习伙伴！"
@export var greeting_en: String = "Hello! I'm Spark, your language learning companion!"

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var dialogue_trigger: Area2D = $DialogueTrigger

var dialogue_state: String = "idle"  # idle, active
var player_in_range: bool = false

func _ready() -> void:
	dialogue_trigger.body_entered.connect(_on_body_entered)
	dialogue_trigger.body_exited.connect(_on_body_exited)
	sprite.play("idle")

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("get_position") and dialogue_state == "idle":
		player_in_range = true
		sprite.play("greeting")
		
		# 自动触发对话
		trigger_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.has_method("get_position"):
		player_in_range = false

func trigger_dialogue() -> void:
	if dialogue_state != "idle":
		return
	
	dialogue_state = "active"
	
	var npc_name = GameManager.current_lang == "zh" ? npc_name_zh : npc_name_en
	var greeting = GameManager.current_lang == "zh" ? greeting_zh : greeting_en
	
	DialogueManager.start_npc_dialogue(npc_id, greeting)

func get_greeting() -> String:
	return GameManager.current_lang == "zh" ? greeting_zh : greeting_en

func get_npc_name() -> String:
	return GameManager.current_lang == "zh" ? npc_name_zh : npc_name_en

func end_dialogue() -> void:
	dialogue_state = "idle"
	sprite.play("idle")

func set_emotion(emotion: String) -> void:
	sprite.play(emotion)
```

**Step 2: Commit**

```bash
git add apps/godot-client/assets/scripts/components/NPCController.gd
git commit -m "feat: add NPCController with auto-trigger dialogue"
```

---

## Week 3-4: 场景文件与集成测试

### Task 12: 创建 MainMenu.tscn 场景

**Files:**
- Create: `apps/godot-client/assets/scenes/MainMenu.tscn`

**Step 1: 在 Godot 编辑器中创建场景**

1. 打开 Godot 4.3
2. 创建新场景：Node2D 作为根节点
3. 添加节点结构：
   - Background (TextureRect) - 背景图片
   - TitleLabel (Label) - 标题文字
   - CoachOverlay (Control) - 挂载 CoachOverlay.gd
   - LangPanel (Control) - 语言选择面板
   - MainMenuController (Node2D) - 挂载 MainMenuController.gd
4. 保存为 `res://assets/scenes/MainMenu.tscn`

**手动操作** - 需在 Godot 编辑器中完成

---

### Task 13: 创建 SpiritForest.tscn 场景

**Files:**
- Create: `apps/godot-client/assets/scenes/SpiritForest.tscn`

**Step 1: 在 Godot 编辑器中创建场景**

1. 创建新场景：Node2D 作为根节点
2. 添加节点结构：
   - Background (TextureRect)
   - Player (CharacterBody2D) - 挂载 PlayerController.gd
   - SparkNPC (StaticBody2D) - 挂载 NPCController.gd
   - DialogueBox (CanvasLayer) - 挂载 DialogueBox.gd
   - BGMPlayer (AudioStreamPlayer)
3. 保存为 `res://assets/scenes/SpiritForest.tscn`

**手动操作** - 需在 Godot 编辑器中完成

---

### Task 14: 添加输入映射

**Files:**
- Modify: `apps/godot-client/project.godot`

**Step 1: 在 project.godot 中添加输入映射**

```ini
[input]

move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194319,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":65,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194321,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":68,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
]
}
move_up={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194320,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":87,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
]
}
move_down={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":4194322,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
, Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":83,"physical_keycode":0,"key_label":0,"unicode":0,"echo":false,"script":null)
]
}
```

**Step 2: Commit**

```bash
git add apps/godot-client/project.godot
git commit -m "feat: add input mappings for player movement"
```

---

## Week 5: 验证与评估

### Task 15: 运行测试与功能验证

**Step 1: 启动 Godot 项目**

```bash
# 在 Godot 编辑器中打开项目
# 验证 Autoload 正常加载
# 验证场景可以正常运行
```

**Step 2: 功能测试清单**

- [ ] MainMenu 场景可运行
- [ ] 精灵飞入动画流畅
- [ ] 语言选择按钮可点击
- [ ] 选择语言后自动进入 SpiritForest
- [ ] SpiritForest 场景可进入
- [ ] 玩家可移动（WASD/方向键）
- [ ] 靠近 NPC 自动触发对话
- [ ] DialogueBox 显示正常
- [ ] 语音监听状态指示器显示
- [ ] 云端 API 调用成功（需后端服务运行）
- [ ] TTS 播放正常
- [ ] 语音识别正常
- [ ] 对话流程完整

**Step 3: 性能数据收集**

记录以下指标用于评估对比：
- 语音响应延迟（VAD + ASR + LLM + TTS 总耗时）
- 场景加载时间
- 内存占用
- 包体大小

---

### Task 16: 生成评估报告

**Files:**
- Create: `docs/plans/2026-04-27-godot-evaluation-report.md`

**Step 1: 收集数据并填写报告模板**

根据测试结果填写评估报告，对比 Godot vs CocosCreator。

**Step 2: Commit**

```bash
git add docs/plans/2026-04-27-godot-evaluation-report.md
git commit -m "docs: add Godot track Phase 2 evaluation report"
```

---

## 检查点与里程碑

### Week 1 检查点

- ✅ project.godot 配置完成
- ✅ 5 个 Autoload 单例创建
- ✅ GameManager、AudioManager、HybridAPI 可用

### Week 2 检查点

- ✅ DialogueBox、CoachOverlay UI 组件创建
- ✅ MainMenuController、PlayerController、NPCController 创建
- ✅ 脚本无编译错误

### Week 3-4 检查点

- ✅ MainMenu.tscn 可运行
- ✅ SpiritForest.tscn 可运行
- ✅ 完整对话流程可用

### Week 5 检查点

- ✅ 功能测试通过
- ✅ 评估报告产出

---

## 风险与备选方案

| 风险 | 触发条件 | 备选方案 |
|------|----------|----------|
| VAD 不稳定 | 静音检测误触发 | 降低阈值，增加最小录音时长 |
| API 调用失败 | 后端未启动 | Mock 数据测试，显示错误提示 |
| TTS 播放失败 | 音频格式问题 | 使用预录音频临时替代 |

---

## 依赖说明

**外部依赖：**
- Godot 4.3 LTS 需手动安装
- 云端服务需运行（`pnpm dev` 启动后端）
- 美术资产需单独准备（可先用占位图）

**内部依赖：**
- GameManager → 无依赖
- AudioManager → 无依赖
- HybridAPI → AudioManager (TTS 播放)
- VoicePipeline → HybridAPI (发送音频)
- DialogueManager → HybridAPI, VoicePipeline, AudioManager, DialogueBox
