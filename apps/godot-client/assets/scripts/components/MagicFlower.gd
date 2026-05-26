## 魔法花组件
##
## 用于精灵森林颜色任务，语音输入颜色咒语激活对应花朵
##
extends StaticBody2D

@export var flower_color: String = "red"
@export var active_texture: Texture2D
@export var inactive_texture: Texture2D

@onready var sprite: ColorRect = $Sprite

var is_active: bool = false

func get_color() -> String:
	return flower_color

func set_state(state: String) -> void:
	match state:
		"active":
			activate()
		"inactive":
			deactivate()

func activate() -> void:
	is_active = true
	_play_activation_effect()

func deactivate() -> void:
	is_active = false

func _play_activation_effect() -> void:
	"""播放激活效果"""
	# TODO: 添加粒子效果或动画
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.2, 1.2), 0.2)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3)
