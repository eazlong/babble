extends Node2D

@onready var coach_overlay: CoachOverlay = $CoachLayer/CoachOverlay
@onready var lang_panel: Control = $OverlayLayer/LangPanel
@onready var lang_zh_button: Button = $OverlayLayer/LangPanel/LangZhButton
@onready var lang_en_button: Button = $OverlayLayer/LangPanel/LangEnButton
@onready var mic_panel: Control = $OverlayLayer/MicPanel
@onready var mic_icon: ColorRect = $OverlayLayer/MicPanel/MicIcon
@onready var mic_label: Label = $OverlayLayer/MicPanel/MicLabel
@onready var scene_select_panel: Control = $OverlayLayer/SceneSelectPanel
@onready var spirit_forest_button: Button = $OverlayLayer/SceneSelectPanel/SpiritForestButton
@onready var spell_library_button: Button = $OverlayLayer/SceneSelectPanel/SpellLibraryButton
@onready var rainbow_garden_button: Button = $OverlayLayer/SceneSelectPanel/RainbowGardenButton

var selected_lang: String = "zh"
var mic_tween: Tween = null
var mic_active: bool = false
var silence_timer: float = 0.0
var record_duration: float = 0.0
const SILENCE_TIMEOUT: float = 15.0
const MAX_RECORD_DURATION: float = 10.0

func _ready() -> void:
	print("[MainMenu] _ready() called")

	# Initialize SceneManagementSystem with scene configs
	var config_loader: SceneConfigLoader = SceneConfigLoader.new()
	var success: bool = config_loader.load_scene_configs("res://assets/resources/scene_configs/")
	if success:
		var configs: Array = config_loader.get_all_scene_configs().values()
		SceneManagementSystem.initialize(configs)
		print("[MainMenu] SceneManagementSystem initialized with %d configs" % configs.size())
	else:
		push_warning("[MainMenu] Failed to load scene configs")

	lang_panel.visible = false
	lang_panel.modulate.a = 0
	mic_panel.visible = false
	mic_panel.modulate.a = 0
	if scene_select_panel:
		scene_select_panel.visible = false
		scene_select_panel.modulate.a = 0

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
	var welcome_text: String = "喵~ 你好！我是 feifei(腓腓)，你的伴生精灵！你叫什么名字呢？"
	if GameManager.current_lang == "en":
		welcome_text = "Meow~ Hello! I'm feifei, your companion spirit! What's your name?"

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
	var tween: Tween = create_tween()
	var tween_id: int = UITweenManager.register_tween("ui_feedback", tween)
	tween.tween_property(mic_panel, "modulate:a", 1.0, 0.3)

	_start_mic_pulse()

	VoicePipeline.start_listening()
	silence_timer = 0.0
	record_duration = 0.0

func _deactivate_mic() -> void:
	mic_active = false
	VoicePipeline.stop_listening()
	_stop_mic_pulse()

	var tween: Tween = create_tween()
	var tween_id: int = UITweenManager.register_tween("ui_feedback", tween)
	tween.tween_property(mic_panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): mic_panel.visible = false)

func _start_mic_pulse() -> void:
	mic_tween = create_tween()
	var tween_id = UITweenManager.register_tween("ambient", mic_tween)
	mic_tween.set_loops()
	mic_tween.tween_property(mic_icon, "scale", Vector2(1.3, 1.3), 0.6)
	mic_tween.tween_property(mic_icon, "scale", Vector2(1.0, 1.0), 0.6)

func _stop_mic_pulse() -> void:
	if mic_tween:
		mic_tween.kill()
		mic_tween = null

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	print("[MainMenuController] _on_voice_ended triggered! audio_size=", audio_data.size())
	if not mic_active:
		return

	_deactivate_mic()

	coach_overlay.show_hint("正在识别中...", "idle")
	HybridAPI.recognize_speech(audio_data, "en")

func _on_asr_received(result: Dictionary) -> void:
	print("[MainMenu] ASR result: ", result)
	var text: String = HybridAPI.get_asr_corrected_text(result)
	if text.is_empty():
		print("[MainMenu] ASR text empty, showing language panel")
		show_language_panel()
		return

	var detected_lang: String = result.get("language", "zh")
	if detected_lang not in ["zh", "en"]:
		detected_lang = "zh"

	GameManager.set_language(detected_lang)
	selected_lang = detected_lang

	var confirm_text: String = "好的！中文模式！出发吧！"
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

	var tween: Tween = create_tween()
	var tween_id: int = UITweenManager.register_tween("ui_feedback", tween)
	tween.set_parallel(true)
	tween.tween_property(lang_zh_button, "position", Vector2(100, 100), 0.5)
	tween.tween_property(lang_en_button, "position", Vector2(440, 100), 0.5)

	tween.chain()
	tween.tween_property(lang_panel, "modulate:a", 1.0, 0.3)

func _on_lang_zh_button_pressed() -> void:
	selected_lang = "zh"
	GameManager.set_language("zh")

	var confirm_text: String = "好的！中文模式！出发吧！"
	coach_overlay.show_hint(confirm_text, "idle")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "zh")

	await AudioManager.tts_finished
	enter_game_scene()

func _on_lang_en_button_pressed() -> void:
	selected_lang = "en"
	GameManager.set_language("en")

	var confirm_text: String = "Great! English mode! Let's go!"
	coach_overlay.show_hint(confirm_text, "idle")
	HybridAPI.synthesize_tts(confirm_text, "spirit", "en")

	await AudioManager.tts_finished
	enter_game_scene()

func enter_game_scene() -> void:
	# 序章流程：直接进入 BeginningFP（SpiritForest 第一人称改造版）
	get_tree().change_scene_to_file("res://assets/scenes/BeginningFP.tscn")

func _on_spirit_forest_pressed() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/BeginningFP.tscn")

func _on_spell_library_pressed() -> void:
	# 暂时禁用，后续替换为长安西市
	pass

func _on_rainbow_garden_pressed() -> void:
	# 暂时禁用，后续替换为其他国风场景
	pass
