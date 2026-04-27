extends Control
class_name CoachOverlay

@onready var coach_sprite: AnimatedSprite2D = $CoachSprite
@onready var dialogue_bubble: Panel = $DialogueBubble
@onready var dialogue_text: RichTextLabel = $DialogueBubble/DialogueText

@export var fly_duration: float = 4.0

signal fly_in_completed()
signal hint_shown()

func fly_in_from(start_pos: Vector2, end_pos: Vector2, duration: float = fly_duration, callback: Callable = Callable()) -> void:
	print("[CoachOverlay] Starting fly_in animation from ", start_pos, " to ", end_pos)
	coach_sprite.position = start_pos
	coach_sprite.visible = true
	coach_sprite.play("fly")
	print("[CoachOverlay] Sprite visible: ", coach_sprite.visible, " position: ", coach_sprite.position)
	print("[CoachOverlay] Animation playing: ", coach_sprite.animation, " frame: ", coach_sprite.frame)

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

	coach_sprite.play(emotion)

	hint_shown.emit()

func hide_hint() -> void:
	var tween = create_tween()
	tween.tween_property(dialogue_bubble, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): dialogue_bubble.visible = false)

func set_emotion(emotion: String) -> void:
	coach_sprite.play(emotion)
