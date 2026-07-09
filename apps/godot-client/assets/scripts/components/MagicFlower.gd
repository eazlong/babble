## 魔法花组件
##
## 用于精灵森林浇花教学，支持 4 种状态：
## WILTED(枯萎) → INACTIVE(等待) → GROWING(生长中) → BLOOMED(绽放)
##
extends StaticBody2D

enum FlowerState { WILTED = 0, INACTIVE = 1, GROWING = 2, BLOOMED = 3 }

@export var flower_color: String = "red"

@onready var sprite: ColorRect = $Sprite

var _current_state: FlowerState = FlowerState.WILTED

func get_color() -> String:
	return flower_color

func get_flower_state() -> FlowerState:
	return _current_state

# ——— 新 API：FlowerState 枚举 ———

func set_flower_state(state: FlowerState) -> void:
	_current_state = state
	match state:
		FlowerState.WILTED:
			_play_wilted()
		FlowerState.INACTIVE:
			_play_inactive()
		FlowerState.GROWING:
			_play_growth()
		FlowerState.BLOOMED:
			_play_bloomed()

# ——— 旧 API 兼容 ———

func set_state(state: String) -> void:
	match state:
		"active":
			set_flower_state(FlowerState.BLOOMED)
		"inactive":
			set_flower_state(FlowerState.WILTED)

func activate() -> void:
	set_flower_state(FlowerState.BLOOMED)

func deactivate() -> void:
	set_flower_state(FlowerState.WILTED)

# ——— 视觉效果 ———

func _play_wilted() -> void:
	if not sprite:
		return
	# 灰暗+下垂
	sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	sprite.rotation = deg_to_rad(10)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.9, 0.85), 0.3)

func _play_inactive() -> void:
	if not sprite:
		return
	# 恢复正常颜色，等待浇水
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3)

func _play_growth() -> void:
	if not sprite:
		return
	# 发光+粒子+缩放 tween
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.3, 1.3), 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.3) \
		.set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func():
		_current_state = FlowerState.BLOOMED
	)

	# 发光效果
	var glow_tween := create_tween()
	glow_tween.tween_property(sprite, "modulate", Color(1.5, 1.5, 1.2, 1.0), 0.4)
	glow_tween.tween_property(sprite, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6)

func _play_bloomed() -> void:
	if not sprite:
		return
	# 完全绽放
	sprite.modulate = Color(1.1, 1.1, 1.0, 1.0)
	sprite.rotation = 0.0
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.15, 1.15), 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)
