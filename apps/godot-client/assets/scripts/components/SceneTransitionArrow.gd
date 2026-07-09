## 转场箭头按钮
##
## 屏幕右方脉冲箭头，玩家点击触发场景转场
##
extends Control

signal arrow_pressed()

@onready var arrow_button: Button = $ArrowButton if has_node("ArrowButton") else null

func _ready() -> void:
	visible = false
	if arrow_button:
		arrow_button.pressed.connect(_on_arrow_button_pressed)

func show_arrow() -> void:
	visible = true
	modulate.a = 0.0
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_start_pulse()

func hide_arrow() -> void:
	_stop_pulse()
	var fade_tween := create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	fade_tween.tween_callback(func(): visible = false)

func _start_pulse() -> void:
	var pulse_tween := create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.6) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _stop_pulse() -> void:
	# 停止所有 tween（简化处理）
	scale = Vector2(1.0, 1.0)

func _on_arrow_button_pressed() -> void:
	arrow_pressed.emit()
