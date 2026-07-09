## Oakley 化为光点消散效果
##
## 任务完成后 Oakley 化为光点飘散，引导玩家前往下一个场景
## 此文件是 OakleyAnimator.play_dissolve 的补充，
## 专门处理粒子+shader 组合的高级消散效果
##
class_name OakleyDissolve
extends RefCounted

const PARTICLE_COUNT: int = 20
const DISSOLVE_DURATION: float = 1.0
const DRIFT_DISTANCE_X: float = 500.0

## 播放完整消散序列（粒子爆发 + 淡出飘散）
static func play_dissolve(node: Node) -> Tween:
	if not node:
		return null

	# 1. 粒子爆发（调用方负责 VFXManager.play_burst 或使用 magic_activation）
	# 此处仅负责节点本身的淡出+飘散

	# 2. 淡出 + 向右飘散
	var tween := node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "modulate:a", 0.0, DISSOLVE_DURATION)
	tween.tween_property(node, "position:x", node.position.x + DRIFT_DISTANCE_X, DISSOLVE_DURATION) \
		.set_ease(Tween.EASE_IN)
	tween.set_parallel(false)
	tween.tween_callback(func(): node.visible = false)
	return tween
