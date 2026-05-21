extends Node2D

@onready var coach_overlay: CoachOverlay = $CoachOverlay
@onready var lang_panel: Control = $LangPanel
@onready var lang_zh_button: Button = $LangPanel/LangZhButton
@onready var lang_en_button: Button = $LangPanel/LangEnButton
@onready var mic_panel: Control = $MicPanel
@onready var mic_icon: ColorRect = $MicPanel/MicIcon
@onready var mic_label: Label = $MicPanel/MicLabel

var selected_lang: String = "zh"
var mic_tween: Tween
var mic_active: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
const SILENCE_TIMEOUT: float = 15.0
const MAX_RECORD_DURATION: float = 10.0

func _ready() -> void:
	print("[MainMenu] _ready() called")
	lang_panel.visible = false
	lang_panel.modulate.a = 0
	mic_panel.visible = false
	mic_panel.modulate.a = 0

	HybridAPI.ping_services()
	HybridAPI.asr_received.connect(_on_asr_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)

	print("[MainMenu] Calling fly_in_from...")
	coach_overlay.fly_in_from(Vector2(-800, 200), Vector2(540, 300), 2.0, _on_fly_in_completed)

func _process(delta: float) -> void:
	if not mic_active:
		return

	if not VoicePipeline.is_listening:
		return

	if VoicePipeline.is_recording:
		record_duration += delta
		silence_timer = 0.0
		if record_duration > MAX_RECORD_DURATION:
			VoicePipeline.stop_listening()
			_deactivate_mic()
			show_language_panel()
	else:
		silence_timer += delta
		record_duration = 0.0
		if silence_timer > SILENCE_TIMEOUT:
			_deactivate_mic()
			show_language_panel()

func _on_fly_in_completed() -> void:
	var welcome_text = "你好！很高兴认识你，你叫什么名字呢？"
	if GameManager.current_lang == "en":
		welcome_text = "Hello! Ready to learn magic English? Pick your language!"

	coach_overlay.show_hint(welcome_text, "idle")
	HybridAPI.synthesize_tts(welcome_text, "spirit", GameManager.current_lang)

	await AudioManager.tts_finished

	if not _has_record_bus():
		show_language_panel()
		return

	show_mic_panel()

func _has_record_bus() -> bool:
	return AudioServer.get_bus_index("Record") != -1

func show_mic_panel() -> void:
	mic_active = true
	mic_panel.visible = true
	var tween = create_tween()
	tween.tween_property(mic_panel, "modulate:a", 1.0, 0.3)

	_start_mic_pulse()

	var prompt_text = "请对麦克风说中文或英文来选择语言吧！"
	coach_overlay.show_hint(prompt_text, "idle")
	HybridAPI.synthesize_tts(prompt_text, "spirit", GameManager.current_lang)

	await AudioManager.tts_finished

	VoicePipeline.start_listening()
	silence_timer = 0.0
	record_duration = 0.0

func _deactivate_mic() -> void:
	mic_active = false
	VoicePipeline.stop_listening()
	_stop_mic_pulse()

	var tween = create_tween()
	tween.tween_property(mic_panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): mic_panel.visible = false)

func _start_mic_pulse() -> void:
	mic_tween = create_tween()
	mic_tween.set_loops()
	mic_tween.tween_property(mic_icon, "scale", Vector2(1.3, 1.3), 0.6)
	mic_tween.tween_property(mic_icon, "scale", Vector2(1.0, 1.0), 0.6)

func _stop_mic_pulse() -> void:
	if mic_tween:
		mic_tween.kill()
		mic_tween = null

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[MainMenuController] _on_voice_ended triggered!")
	if not mic_active:
		return

	_deactivate_mic()

	coach_overlay.show_hint("正在识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "auto")

func _on_asr_received(result: Dictionary) -> void:
	var text: String = result.get("text", "")
	if text.is_empty():
		show_language_panel()
		return

	var detected_lang: String = result.get("language", "zh")
	if detected_lang not in ["zh", "en"]:
		detected_lang = "zh"

	GameManager.set_language(detected_lang)
	selected_lang = detected_lang

	var confirm_text = "好的！中文模式！出发吧！"
	if detected_lang == "en":
		confirm_text = "Great! English mode! Let's go!"

	coach_overlay.show_hint(confirm_text, "idle")
	HybridAPI.synthesize_tts(confirm_text, "spirit", detected_lang)

	await AudioManager.tts_finished
	enter_game_scene()

func show_language_panel() -> void:
	lang_panel.visible = true

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
	coach_overlay.show_hint(confirm_text, "idle")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "zh")

	await AudioManager.tts_finished
	enter_game_scene()

func _on_lang_en_button_pressed() -> void:
	selected_lang = "en"
	GameManager.set_language("en")

	var confirm_text = "Great! English mode! Let's go!"
	coach_overlay.show_hint(confirm_text, "idle")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "en")

	await AudioManager.tts_finished
	enter_game_scene()

func enter_game_scene() -> void:
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://assets/scenes/SpiritForest.tscn")
