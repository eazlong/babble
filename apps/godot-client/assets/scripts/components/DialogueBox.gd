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
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(voice_indicator, "modulate:a", 0.5, 0.5)
	tween.tween_property(voice_indicator, "modulate:a", 1.0, 0.5)

func hide_voice_listening() -> void:
	voice_indicator.visible = false