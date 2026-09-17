## 随机眨眼控制器：每 2~6 秒随机触发一次眨眼，10% 概率连眨两次。
##
## 实现方式（P1 并发修正）：用节点绑定 Tween 直接驱动 eyes:polygon，
## 不经过 AnimationPlayer —— Godot 4.6 的 AnimationPlayer 是单播放状态
## （无图层 API），play() 会顶掉正在播的动画（blink 曾把 talk_mouth 顶掉，
## 且 blink 结束后口型循环不会自动恢复）。
## 三个驱动器、三组互不相交的属性，可真正并行：
##   AnimationPlayer（身体）  → 骨骼 + 面部 position/rotation/scale
##   FaceAnimationPlayer（嘴）→ mouth:polygon（talk_mouth 循环）
##   本控制器（眼，Tween）    → eyes:polygon
class_name BlinkController
extends Node

@export var min_interval: float = 2.0
@export var max_interval: float = 6.0
@export var double_blink_chance: float = 0.1
@export var double_blink_gap: float = 0.35

## 眨眼三段时长（与原 blink 动画关键帧一致：睁→半闭 0.08 / 半闭→闭 0.07 / 闭→睁 0.09）
@export var phase1_duration: float = 0.08
@export var phase2_duration: float = 0.07
@export var phase3_duration: float = 0.09
## 收缩因子（y' = cy + factor·(y−cy)，x 不变）
@export var half_closed_factor: float = 0.5
@export var closed_factor: float = 0.05
## 眼睛几何中心 y（eyes 节点 offset=(0,0)，顶点 bbox 中心 ≈216）
@export var eyes_center_y: float = 216.0

@export var eyes_polygon: Polygon2D

## 为 true 时暂停眨眼（如惊讶表情期间）
var paused: bool = false

var _base_polygon: PackedVector2Array
var _half_closed: PackedVector2Array
var _closed: PackedVector2Array

func _ready() -> void:
	# 兜底：若场景未注入 eyes_polygon（NodePath 解析失败等），按相对路径自查找
	if eyes_polygon == null:
		eyes_polygon = get_node_or_null(NodePath("../polygons/eyes")) as Polygon2D
	if eyes_polygon == null:
		push_warning("BlinkController: 找不到 eyes_polygon，眨眼禁用")
		return
	_base_polygon = eyes_polygon.polygon.duplicate()
	_half_closed = _shrink(_base_polygon, half_closed_factor)
	_closed = _shrink(_base_polygon, closed_factor)
	_schedule()

## 顶点向中心 y 收缩
func _shrink(poly: PackedVector2Array, factor: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in poly:
		out.append(Vector2(v.x, eyes_center_y + factor * (v.y - eyes_center_y)))
	return out

func _schedule() -> void:
	if eyes_polygon == null:
		return
	var delay: float = randf_range(min_interval, max_interval)
	# 节点绑定 tween：节点释放时等待自动取消，无僵尸协程
	await create_tween().tween_interval(delay).finished
	if paused:
		_schedule()
		return
	_do_blink()

func _do_blink() -> void:
	if eyes_polygon == null:
		_schedule()
		return
	_do_one_blink()
	if randf() < double_blink_chance:
		await create_tween().tween_interval(double_blink_gap).finished
		_do_one_blink()
	_schedule()

func _do_one_blink() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(eyes_polygon, "polygon", _half_closed, phase1_duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(eyes_polygon, "polygon", _closed, phase2_duration).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(eyes_polygon, "polygon", _base_polygon, phase3_duration).set_trans(Tween.TRANS_LINEAR)
	await tw.finished
