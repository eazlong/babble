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

# ── Idle Loop ──

func _start_idle_loop() -> void:
	_kill_idle_tweens()

	var pos = _base_position

	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(coach_sprite, "position:y", pos.y - 6, 2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(coach_sprite, "position:y", pos.y + 6, 2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	_breathe_tween = create_tween()
	_breathe_tween.set_loops()
	_breathe_tween.tween_property(coach_sprite, "scale", Vector2(1.04, 1.04), 2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_breathe_tween.tween_property(coach_sprite, "scale", Vector2(1.0, 1.0), 2.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _kill_idle_tweens() -> void:
	if _idle_tween and _idle_tween.is_valid():
		_idle_tween.kill()
	if _breathe_tween and _breathe_tween.is_valid():
		_breathe_tween.kill()

# ── State: idle ──

func _play_idle() -> void:
	coach_sprite.visible = true
	coach_sprite.modulate = Color.WHITE
	_play_sprite_animation(STATE_IDLE)
	_hide_bubble()
	_start_idle_loop()

# ── State: enter ──

func _play_enter() -> void:
	coach_sprite.visible = true
	coach_sprite.modulate.a = 0
	coach_sprite.scale = Vector2(0.8, 0.8)

	_state_tween = create_tween()
	_state_tween.set_parallel(true)
	_state_tween.tween_property(coach_sprite, "modulate:a", 1.0, 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_state_tween.tween_property(coach_sprite, "scale", Vector2(1.0, 1.0), 0.5) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_state_tween.set_parallel(false)
	_state_tween.tween_callback(func():
		_current_state = STATE_IDLE
		_play_idle()
	)

	_play_sprite_animation(STATE_ENTER)

# ── State: exit ──

func _play_exit() -> void:
	_state_tween = create_tween()
	_state_tween.set_parallel(true)
	_state_tween.tween_property(coach_sprite, "modulate:a", 0.0, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_state_tween.tween_property(coach_sprite, "scale", Vector2(0.7, 0.7), 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_state_tween.set_parallel(false)
	_state_tween.tween_callback(func():
		coach_sprite.visible = false
		_is_present = false
		_hide_bubble()
	)

	_play_sprite_animation(STATE_EXIT)

func _play_speaking() -> void:
	_kill_idle_tweens()
	coach_sprite.modulate = Color.WHITE

	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y - 4, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y + 4, 0.8) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	_play_sprite_animation(STATE_SPEAKING)


func _play_hint_state() -> void:
	_kill_idle_tweens()
	coach_sprite.modulate = Color.WHITE

	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y - 3, 2.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y + 3, 2.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	_play_sprite_animation(STATE_HINT)


func _play_thinking() -> void:
	_kill_idle_tweens()

	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y - 3, 3.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(coach_sprite, "position:y", _base_position.y + 3, 3.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	_state_tween = create_tween()
	_state_tween.tween_property(coach_sprite, "modulate", Color(1.2, 1.2, 1.2, 1.0), 0.5) \
		.set_ease(Tween.EASE_IN_OUT)

	_play_sprite_animation(STATE_THINKING)


func _play_happy(_text_override: String = "") -> void:
	_state_tween = create_tween()
	_state_tween.tween_property(coach_sprite, "position:y", _base_position.y - 15, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_state_tween.parallel()
	_state_tween.tween_property(coach_sprite, "scale", Vector2(1.15, 1.15), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_state_tween.tween_property(coach_sprite, "scale", Vector2(1.0, 1.0), 0.4) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_ELASTIC)
	_state_tween.parallel()
	_state_tween.tween_property(coach_sprite, "position:y", _base_position.y, 0.4) \
		.set_ease(Tween.EASE_IN_OUT)
	_state_tween.tween_callback(func():
		if _text_override != "":
			_show_bubble(_text_override)
			_bubble_ttl_timer.start(2.0)
		_current_state = STATE_IDLE
		coach_sprite.modulate = Color.WHITE
		_play_sprite_animation(STATE_IDLE)
		_start_idle_loop()
	)

	_play_sprite_animation(STATE_HAPPY)

func _show_bubble(_text: String) -> void:
	if _bubble_tween and _bubble_tween.is_valid():
		_bubble_tween.kill()

	dialogue_text.text = _text
	dialogue_bubble.visible = true
	dialogue_bubble.modulate.a = 0
	dialogue_bubble.scale = Vector2(0.9, 0.9)

	_bubble_tween = create_tween()
	_bubble_tween.set_parallel(true)
	_bubble_tween.tween_property(dialogue_bubble, "modulate:a", 1.0, 0.3) \
		.set_ease(Tween.EASE_OUT)
	_bubble_tween.tween_property(dialogue_bubble, "scale", Vector2(1.0, 1.0), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_bubble() -> void:
	if _bubble_tween and _bubble_tween.is_valid():
		_bubble_tween.kill()

	_bubble_tween = create_tween()
	_bubble_tween.tween_property(dialogue_bubble, "modulate:a", 0.0, 0.25) \
		.set_ease(Tween.EASE_IN)
	_bubble_tween.tween_callback(func():
		dialogue_bubble.visible = false
	)

func _stop_bubble_ttl() -> void:
	_bubble_ttl_timer.stop()

func _on_bubble_ttl_timeout() -> void:
	_hide_bubble()
	if _current_state in [STATE_SPEAKING, STATE_HINT]:
		_current_state = STATE_IDLE
		_play_idle()

# ── Legacy API Compatibility ──

func fly_in_from(start_pos: Vector2, end_pos: Vector2, duration: float = fly_duration, callback: Callable = Callable()) -> void:
	_kill_all_tweens()

	coach_sprite.position = start_pos
	coach_sprite.visible = true
	coach_sprite.modulate.a = 1.0
	coach_sprite.modulate = Color.WHITE
	coach_sprite.scale = Vector2(1.0, 1.0)
	_is_present = true

	_play_sprite_animation("fly")

	_state_tween = create_tween()
	_state_tween.set_ease(Tween.EASE_IN_OUT)
	_state_tween.set_trans(Tween.TRANS_QUAD)
	_state_tween.tween_property(coach_sprite, "position", end_pos, duration)

	if callback.is_valid():
		_state_tween.tween_callback(callback)
	else:
		_state_tween.tween_callback(func():
			fly_in_completed.emit()
			_base_position = end_pos
			_current_state = STATE_IDLE
			_play_idle()
		)

func show_hint(text: String, emotion: String = "neutral") -> void:
	var state = STATE_HINT
	if emotion in PRIORITY:
		state = emotion
	play_state(state, text)
	hint_shown.emit()

func show_hint_for_duration(text: String, emotion: String, ttl_ms: int) -> void:
	var state = STATE_HINT
	if emotion in PRIORITY:
		state = emotion
	play_state(state, text, ttl_ms)

func set_emotion(emotion: String) -> void:
	if emotion in PRIORITY:
		play_state(emotion)
	elif _has_animation(emotion):
		coach_sprite.play(emotion)

func hide_hint() -> void:
	_hide_bubble()
	if _current_state == STATE_HINT or _current_state == STATE_SPEAKING:
		_current_state = STATE_IDLE
		_play_idle()

# ── Main Public API ──

func play_state(state: String, text: String = "", ttl_ms: int = 0) -> void:
	if not state in PRIORITY:
		printerr("[CoachOverlay] Unknown state: ", state)
		return

	if not _is_present and state not in [STATE_ENTER, STATE_EXIT]:
		return

	var new_priority: int = PRIORITY[state]
	var current_priority: int = PRIORITY[_current_state]
	if new_priority < current_priority:
		return

	if state == STATE_HAPPY:
		_kill_all_tweens()
		_current_state = STATE_HAPPY
		_play_happy(text)
		return

	_current_state = state
	_kill_all_tweens()
	_stop_bubble_ttl()

	match state:
		STATE_IDLE:
			_play_idle()
		STATE_ENTER:
			_play_enter()
		STATE_EXIT:
			_play_exit()
		STATE_SPEAKING:
			_play_speaking()
		STATE_HINT:
			_play_hint_state()
		STATE_THINKING:
			_play_thinking()

	if text != "":
		_show_bubble(text)
		if ttl_ms > 0:
			_bubble_ttl_timer.start(float(ttl_ms) / 1000.0)
	elif not state in STATES_WITH_BUBBLE:
		_hide_bubble()

func show_presence() -> void:
	_is_present = true
	play_state(STATE_ENTER)

func hide_presence() -> void:
	play_state(STATE_EXIT)
