## 大树微光脉冲效果
##
## 当 Spark 引导玩家注视大树时，大树产生微光脉冲吸引注意力
##
class_name BigTreeGlow
extends RefCounted

## 启动大树脉冲发光效果（循环，直到 stop 被调用）
static func start_pulse(tree_node: Node) -> Tween:
	if not tree_node:
		return null
	var tween := tree_node.create_tween()
	tween.set_loops()
	tween.tween_property(tree_node, "modulate", Color(1.3, 1.3, 1.0, 1.0), 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(tree_node, "modulate", Color.WHITE, 1.0) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	return tween

## 停止脉冲，恢复原始颜色
static func stop_pulse(tree_node: Node, tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()
	if tree_node:
		tree_node.modulate = Color.WHITE
