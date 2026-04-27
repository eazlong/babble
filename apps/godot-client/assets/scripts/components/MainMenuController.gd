extends Node2D

@onready var coach_overlay: CoachOverlay = $CoachOverlay
@onready var lang_panel: Control = $LangPanel
@onready var lang_zh_button: Button = $LangPanel/LangZhButton
@onready var lang_en_button: Button = $LangPanel/LangEnButton

var selected_lang: String = "zh"

func _ready() -> void:
	lang_panel.visible = false
	lang_panel.modulate.a = 0

	HybridAPI.ping_services()

	coach_overlay.fly_in_from(Vector2(800, 300), Vector2(540, 300), 4.0, _on_fly_in_completed)

func _on_fly_in_completed() -> void:
	var welcome_text = "你好！准备好学习魔法英语了吗？选择你的语言吧！"
	if GameManager.current_lang == "en":
		welcome_text = "Hello! Ready to learn magic English? Pick your language!"

	coach_overlay.show_hint(welcome_text, "happy")

	HybridAPI.synthesize_tts(welcome_text, "spirit", GameManager.current_lang)

	show_language_panel()

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