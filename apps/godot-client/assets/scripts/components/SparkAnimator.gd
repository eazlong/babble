## Spark 动画控制器
##
## 管理 Spark 在精灵森林场景内的位置移动与动画状态：
## - 飞入（远处→肩膀）
## - 落肩膀（idle 呼吸）
## - 飞中央（屏幕中央，面向玩家）
## - 指向（手指左方）
##
class_name SparkAnimator
extends RefCounted

const FLY_DURATION: float = 0.8

## 移动 Spark 到指定位置（使用 tween）
static func move_to(spark_node: Node2D, target_pos: Vector2, duration: float = FLY_DURATION) -> Tween:
	if not spark_node:
		return null
	spark_node.visible = true
	var tween := spark_node.create_tween()
	if duration <= 0.0:
		spark_node.position = target_pos
		return tween
	tween.tween_property(spark_node, "position", target_pos, duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	return tween

## Spark 从屏幕外飞入到肩膀
static func fly_in_from_offscreen(spark_node: Node2D, shoulder_pos: Vector2, offscreen_pos: Vector2) -> Tween:
	if not spark_node:
		return null
	spark_node.position = offscreen_pos
	spark_node.visible = true
	return move_to(spark_node, shoulder_pos, FLY_DURATION)
