## Oakley 动画控制器
##
## 管理大树精灵 Oakley 的状态动画：
## - 苏醒（淡入）
## - 说话（轻微缩放脉冲）
## - 闭眼等待（降低透明度 + 呼吸）
## - 化为光点（淡出 + 向右飘散）
##
class_name OakleyAnimator
extends RefCounted

const WAKE_DURATION: float = 1.5
const DISSOLVE_DURATION: float = 1.0
const SLEEP_ALPHA: float = 0.5

## Oakley 苏醒：从透明淡入到完全可见
static func play_wake(node: Node) -> Tween:
	if not node:
		return null
	node.visible = true
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, WAKE_DURATION) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	return tween

## Oakley 进入等待状态：降低透明度
static func play_sleep(node: Node) -> Tween:
	if not node:
		return null
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", SLEEP_ALPHA, 0.8) \
		.set_ease(Tween.EASE_IN_OUT)
	return tween

## Oakley 苏醒（从 sleep 状态恢复）
static func play_wake_from_sleep(node: Node) -> Tween:
	if not node:
		return null
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.5)
	return tween

## Oakley 化为光点：淡出 + 向右飘散 + 粒子爆发
static func play_dissolve(node: Node) -> Tween:
	if not node:
		return null
	# 粒子爆发（调用方需要先触发 VFXManager）
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "modulate:a", 0.0, DISSOLVE_DURATION)
	tween.tween_property(node, "position:x", node.position.x + 500.0, DISSOLVE_DURATION) \
		.set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(func(): node.visible = false)
	return tween
