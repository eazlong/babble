## 宝箱组件
##
## 用于精灵森林数字任务，语音输入正确数字解锁
##
extends StaticBody2D

@export var is_locked: bool = true
@export var locked_texture: Texture2D
@export var unlocked_texture: Texture2D

@onready var sprite: ColorRect = $Sprite
@onready var interaction_area: Area2D = $InteractionArea

signal chest_unlocked()

func _ready() -> void:
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player") and not is_locked:
		# 玩家可以打开已解锁的宝箱
		open_chest()

func set_locked(locked: bool) -> void:
	is_locked = locked

	if not locked:
		chest_unlocked.emit()
		# 播放解锁动画
		_play_unlock_effect()

func open_chest() -> void:
	"""打开宝箱"""
	# TODO: 显示奖励 UI
	print("[TreasureChest] Chest opened!")

func _play_unlock_effect() -> void:
	"""播放解锁效果"""
	if sprite:
		var tween = create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.1, 1.1), 0.3)
		tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.2)
