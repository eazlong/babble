extends Control
class_name CoachOverlay

# ── State Constants ──

const STATE_IDLE = "idle"
const STATE_ENTER = "enter"
const STATE_EXIT = "exit"
const STATE_SPEAKING = "speaking"
const STATE_HINT = "hint"
const STATE_THINKING = "thinking"
const STATE_HAPPY = "happy"

const PRIORITY: Dictionary = {
	STATE_IDLE: 0,
	STATE_THINKING: 1,
	STATE_HAPPY: 2,
	STATE_HINT: 3,
	STATE_SPEAKING: 4,
	STATE_ENTER: 5,
	STATE_EXIT: 6,
}

const STATES_WITH_BUBBLE: Array[String] = [STATE_SPEAKING, STATE_HINT]

# ── Node References ──

@onready var coach_sprite: AnimatedSprite2D = $CoachSprite
@onready var dialogue_bubble: Panel = $DialogueBubble
@onready var dialogue_text: RichTextLabel = $DialogueBubble/DialogueText

@export var fly_duration: float = 4.0

# ── Internal State ──

var _current_state: String = STATE_IDLE
var _is_present: bool = true
var _base_position: Vector2
var _idle_tween: Tween
var _breathe_tween: Tween
var _state_tween: Tween
var _bubble_tween: Tween
var _bubble_ttl_timer: Timer

# ── Signals ──

signal fly_in_completed()
signal hint_shown()

# ── Lifecycle ──

func _ready() -> void:
	DialogueManager.coach_overlay = self
	_base_position = coach_sprite.position

	_bubble_ttl_timer = Timer.new()
	_bubble_ttl_timer.one_shot = true
	_bubble_ttl_timer.timeout.connect(_on_bubble_ttl_timeout)
	add_child(_bubble_ttl_timer)

	dialogue_bubble.visible = false
	dialogue_bubble.modulate.a = 0

	_start_idle_loop()

# ── Utilities ──

func _has_animation(anim_name: String) -> bool:
	if not coach_sprite.sprite_frames:
		return false
	return coach_sprite.sprite_frames.has_animation(anim_name)

func _kill_all_tweens() -> void:
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()
	if _state_tween and _state_tween.is_valid():
		_state_tween.kill()
	if _bubble_tween and _bubble_tween.is_valid():
		_bubble_tween.kill()

func _play_sprite_animation(anim_name: String) -> void:
	if _has_animation(anim_name):
		coach_sprite.play(anim_name)
	elif _has_animation(STATE_IDLE):
		coach_sprite.play(STATE_IDLE)

# ── Stubs (to be implemented in later tasks) ──

func _start_idle_loop() -> void:
	pass

func _kill_idle_tweens() -> void:
	pass

func _play_idle() -> void:
	pass

func _play_enter() -> void:
	pass

func _play_exit() -> void:
	pass

func _play_speaking() -> void:
	pass

func _play_hint_state() -> void:
	pass

func _play_thinking() -> void:
	pass

func _play_happy(_text_override: String = "") -> void:
	pass

func _show_bubble(_text: String) -> void:
	pass

func _hide_bubble() -> void:
	pass

func _stop_bubble_ttl() -> void:
	pass

func _on_bubble_ttl_timeout() -> void:
	pass

# ── Legacy API stubs (full impl in Task 6) ──

func fly_in_from(start_pos: Vector2, end_pos: Vector2, duration: float = fly_duration, callback: Callable = Callable()) -> void:
	coach_sprite.position = end_pos
	coach_sprite.visible = true
	_base_position = end_pos
	if callback.is_valid():
		callback.call()
	else:
		fly_in_completed.emit()

func show_hint(text: String, emotion: String = "neutral") -> void:
	dialogue_text.text = text
	dialogue_bubble.visible = true
	dialogue_bubble.modulate.a = 1.0
	hint_shown.emit()

func show_hint_for_duration(text: String, emotion: String, ttl_ms: int) -> void:
	show_hint(text, emotion)
	await get_tree().create_timer(float(ttl_ms) / 1000.0).timeout
	hide_hint()

func set_emotion(emotion: String) -> void:
	if _has_animation(emotion):
		coach_sprite.play(emotion)

func hide_hint() -> void:
	dialogue_bubble.visible = false
	dialogue_bubble.modulate.a = 0.0

func play_state(_state: String, _text: String = "", _ttl_ms: int = 0) -> void:
	pass

func show_presence() -> void:
	pass

func hide_presence() -> void:
	pass
