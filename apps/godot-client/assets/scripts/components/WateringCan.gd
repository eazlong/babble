## 水壶交互组件
##
## 从树冠降下 → 可点击 → 飞入玩家手中
##
extends StaticBody2D

signal tapped()

@export var hand_position: Vector2 = Vector2(0, 700)

var _is_tapped: bool = false

func _ready() -> void:
	visible = false
	# 连接 Area2D 输入事件（如果有 InteractionArea 子节点）
	if has_node("InteractionArea"):
		var area: Area2D = $InteractionArea
		area.input_event.connect(_on_input_event)
	else:
		# 使用自身作为 Area2D（如果自身是 StaticBody2D + CollisionShape）
		pass

func descend_from(start_pos: Vector2, duration: float = 1.0) -> void:
	visible = true
	position = start_pos
	var tween := create_tween()
	tween.tween_property(self, "position:y", start_pos.y + 200, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await tween.finished

func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if _is_tapped:
		return
	if event is InputEventMouseButton and event.pressed:
		_is_tapped = true
		tapped.emit()
		_fly_to_player()

func _fly_to_player() -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", hand_position, 0.5) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tween.finished

func reset() -> void:
	_is_tapped = false
	visible = false
