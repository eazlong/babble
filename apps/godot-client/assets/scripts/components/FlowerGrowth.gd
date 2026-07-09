## 花朵生长动画组件
##
## 管理单朵花的生长动画：WILTED → GROWING → BLOOMED
## 可挂载到 MagicFlower 节点，或由控制器调用
##
class_name FlowerGrowth
extends RefCounted

## 生长动画时长（秒）
const GROWTH_DURATION: float = 1.5
const BLOOM_SCALE: Vector2 = Vector2(1.15, 1.15)
const WILTED_SCALE: Vector2 = Vector2(0.9, 0.85)
const FULL_SCALE: Vector2 = Vector2(1.0, 1.0)

## 构造生长 tween 动画序列（返回 Tween 供调用方 await）
static func play_growth_tween(node: Node, sprite: Node) -> Tween:
	if not sprite:
		return null
	var tween := node.create_tween()
	# 放大到 overshoot
	tween.tween_property(sprite, "scale", BLOOM_SCALE, GROWTH_DURATION * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 回弹到正常
	tween.tween_property(sprite, "scale", FULL_SCALE, GROWTH_DURATION * 0.3) \
		.set_ease(Tween.EASE_IN_OUT)
	# 发光效果
	var glow_tween := node.create_tween()
	glow_tween.tween_property(sprite, "modulate", Color(1.5, 1.5, 1.2, 1.0), GROWTH_DURATION * 0.4)
	glow_tween.tween_property(sprite, "modulate", Color.WHITE, GROWTH_DURATION * 0.4)
	return tween

## 构造枯萎状态
static func apply_wilted(sprite: Node) -> void:
	if not sprite:
		return
	sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)
	sprite.rotation = deg_to_rad(10.0)
	sprite.scale = WILTED_SCALE

## 构造等待状态（INACTIVE：正常颜色，等待浇水）
static func apply_inactive(sprite: Node) -> void:
	if not sprite:
		return
	sprite.modulate = Color.WHITE
	sprite.rotation = 0.0
	sprite.scale = FULL_SCALE
