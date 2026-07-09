## 第一人称节点式导航器
##
## 管理场景内5个观察节点的切换：
## - 节点A: 森林入口 (50%, 85%)
## - 节点B: 大树前/TreeSpirit (50%, 60%)
## - 节点C: 魔法花丛 (70%, 55%)
## - 节点D: 小溪边 (30%, 65%)
## - 节点E: 宝箱前 (80%, 70%)
##
## 切换时执行0.8秒淡入淡出过渡。
class_name FirstPersonNavigator
extends Node

# ——— 节点定义 ———
enum FPNode { A_ENTRY, B_TREE, C_FLOWERS, D_STREAM, E_CHEST }

## 每个节点的屏幕百分比坐标
const NODE_POSITIONS: Dictionary = {
	FPNode.A_ENTRY: Vector2(0.50, 0.85),
	FPNode.B_TREE: Vector2(0.50, 0.60),
	FPNode.C_FLOWERS: Vector2(0.70, 0.55),
	FPNode.D_STREAM: Vector2(0.30, 0.65),
	FPNode.E_CHEST: Vector2(0.80, 0.70),
}

## 节点名称（调试用）
const NODE_NAMES: Dictionary = {
	FPNode.A_ENTRY: "森林入口",
	FPNode.B_TREE: "古树前",
	FPNode.C_FLOWERS: "魔法花丛",
	FPNode.D_STREAM: "小溪边",
	FPNode.E_CHEST: "宝箱前",
}

# ——— 过渡参数 ———
const TRANSITION_DURATION: float = 0.8
const FADE_HALF: float = TRANSITION_DURATION * 0.5
const TRANSITION_COLOR: Color = Color(0.1, 0.15, 0.1, 1.0)

# ——— 节点引用 ———
var _fade_overlay: ColorRect
var _current_node: FPNode = FPNode.A_ENTRY
var _is_transitioning: bool = false

# ——— 信号 ———
signal node_changed(new_node: FPNode)
signal transition_started(from_node: FPNode, to_node: FPNode)
signal transition_completed(at_node: FPNode)

# ——— 生命周期 ———

func _ready() -> void:
	_fade_overlay = ColorRect.new()
	_fade_overlay.color = TRANSITION_COLOR
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_overlay.visible = false
	# 添加到UI层
	_add_to_ui_layer.call_deferred()

## 导航到指定节点
func navigate_to(target: FPNode) -> void:
	if _is_transitioning:
		return
	if target == _current_node:
		return

	_is_transitioning = true
	transition_started.emit(_current_node, target)

	var tween: Tween = create_tween()
	tween.tween_callback(_show_fade)
	tween.tween_property(_fade_overlay, "color:a", 1.0, FADE_HALF) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_switch_node.bind(target))
	tween.tween_property(_fade_overlay, "color:a", 0.0, FADE_HALF) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(_complete_transition)

func _show_fade() -> void:
	if _fade_overlay:
		_fade_overlay.visible = true

func _switch_node(target: FPNode) -> void:
	_current_node = target
	node_changed.emit(target)

func _complete_transition() -> void:
	if _fade_overlay:
		_fade_overlay.visible = false
		_fade_overlay.color.a = 0.0
	_is_transitioning = false
	transition_completed.emit(_current_node)

# ——— 查询 ———

func get_current_node() -> FPNode:
	return _current_node

func get_current_node_name() -> String:
	return NODE_NAMES.get(_current_node, "")

func get_current_position() -> Vector2:
	return NODE_POSITIONS.get(_current_node, Vector2(0.5, 0.5))

func is_transitioning() -> bool:
	return _is_transitioning

## 获取从当前位置到目标节点的方向（用于指南针）
func get_direction_to(target: FPNode) -> Vector2:
	var from: Vector2 = get_current_position()
	var to: Vector2 = NODE_POSITIONS.get(target, from)
	return (to - from).normalized()

# ——— 内部 ———

func _add_to_ui_layer() -> void:
	# 将fade overlay添加到场景根节点（作为全屏遮罩）
	var scene_root: Node = get_tree().current_scene
	if scene_root and scene_root.has_node("HUDLayer"):
		var hud_layer: CanvasLayer = scene_root.get_node("HUDLayer")
		_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		hud_layer.add_child(_fade_overlay)
	else:
		# fallback: 添加到当前节点
		get_parent().add_child(_fade_overlay)
		_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
