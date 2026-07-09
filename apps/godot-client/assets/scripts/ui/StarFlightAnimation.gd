## StarFlightAnimation.gd
## 星星飞行动画完整实现 — 贝塞尔曲线 + 旋转 + 落地弹跳
## 设计目标：流畅的星星收集动画，贝塞尔曲线路径，720°旋转
## Godot 4.6, GDScript static typing

class_name StarFlightAnimation
extends Node

## ============================================================
## 配置参数
## ============================================================

## 贝塞尔曲线控制点偏移（抛物线高度）
const BEZIER_CONTROL_OFFSET: Vector2 = Vector2(0, -200)

## TweenManager引用
var _tween_manager: UITweenManager

## ============================================================
## 初始化
## ============================================================

func _init(tween_manager: UITweenManager = null) -> void:
    _tween_manager = tween_manager

## ============================================================
## 播放星星飞行动画
## ============================================================

func play(
    star_node: Control,
    start_pos: Vector2,
    end_pos: Vector2,
    on_complete: Callable = Callable()
) -> void:
    ## 设置初始状态
    star_node.global_position = start_pos
    star_node.scale = Vector2(1.0, 1.0)
    star_node.rotation_degrees = 0.0
    star_node.visible = true
    star_node.modulate.a = 1.0

    ## 创建主Tween（位置）
    var pos_tween = star_node.create_tween()
    pos_tween.set_parallel(true)

    ## 1. 位置动画 (贝塞尔曲线)
    _animate_bezier_flight(pos_tween, star_node, start_pos, end_pos)

    ## 2. 旋转动画 (720°)
    var rotate_tween = star_node.create_tween()
    rotate_tween.tween_property(star_node, "rotation_degrees",
        UIAnimationPresets.StarCollect.ROTATION,
        UIAnimationPresets.StarCollect.FLY_DURATION)

    ## 3. 缩放动画 (先放大再缩小)
    var scale_tween = star_node.create_tween()
    scale_tween.set_trans(Tween.TRANS_QUAD)
    scale_tween.set_ease(Tween.EASE_IN_OUT)
    scale_tween.tween_property(star_node, "scale",
        Vector2(1.3, 1.3), UIAnimationPresets.StarCollect.FLY_DURATION * 0.5)
    scale_tween.tween_property(star_node, "scale",
        Vector2(0.8, 0.8), UIAnimationPresets.StarCollect.FLY_DURATION * 0.5)

    ## 序列化完成回调
    pos_tween.set_parallel(false)
    pos_tween.tween_callback(func():
        _on_star_landed(star_node)
        if on_complete.is_valid():
            on_complete.call()
    )

    ## 注册到TweenManager（如果有）
    if _tween_manager:
        _tween_manager.register_tween("star_flight", pos_tween)

## ============================================================
## 贝塞尔曲线路径动画
## ============================================================

func _animate_bezier_flight(
    tween: Tween,
    star_node: Control,
    start: Vector2,
    end: Vector2
) -> void:
    ## 计算控制点 (形成弧线)
    var mid = (start + end) / 2.0
    var control = mid + BEZIER_CONTROL_OFFSET

    ## 使用tween_method实现贝塞尔插值
    var duration = UIAnimationPresets.StarCollect.FLY_DURATION

    tween.tween_method(
        func(t: float):
            var pos = _quadratic_bezier(start, control, end, t)
            star_node.global_position = pos
        , 0.0, 1.0, duration
    )

## ============================================================
## 二次贝塞尔曲线计算
## ============================================================

func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
    var u = 1.0 - t
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2

## ============================================================
## 星星落地效果
## ============================================================

func _on_star_landed(star_node: Control) -> void:
    ## 短暂放大后消失（落地冲击）
    var tween = star_node.create_tween()
    tween.set_trans(Tween.TRANS_BACK)
    tween.set_ease(Tween.EASE_OUT)

    ## 落地冲击
    tween.tween_property(star_node, "scale", Vector2(1.2, 1.2), 0.1)
    tween.tween_property(star_node, "scale", Vector2(0.0, 0.0), 0.15)
    tween.tween_callback(func(): star_node.visible = false)

## ============================================================
## 星星条增长动画
## ============================================================

func animate_star_bar_progress(
    progress_bar: ProgressBar,
    from_value: float,
    to_value: float
) -> Tween:
    progress_bar.value = from_value

    var tween = progress_bar.create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(progress_bar, "value", to_value, 0.4)

    ## 到达阈值时的震动反馈
    if to_value >= 20.0:  ## Badge解锁阈值
        tween.tween_callback(func():
            _play_milestone_feedback(progress_bar)
        )

    return tween

## ============================================================
## 里程碑反馈 (震动+发光)
## ============================================================

func _play_milestone_feedback(target: Control) -> void:
    var original_pos = target.position

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_ELASTIC)
    tween.set_ease(Tween.EASE_OUT)

    ## 左右震动3次
    for i in range(3):
        tween.tween_property(target, "position:x", original_pos.x + 5, 0.05)
        tween.tween_property(target, "position:x", original_pos.x - 5, 0.05)

    tween.tween_property(target, "position:x", original_pos.x, 0.1)

## ============================================================
## 批量星星飞行
## ============================================================

func play_batch_star_flight(
    star_nodes: Array[Control],
    start_positions: Array[Vector2],
    end_positions: Array[Vector2],
    on_complete: Callable = Callable()
) -> void:
    var completed_count = 0
    var total_count = star_nodes.size()

    for i in range(total_count):
        var star = star_nodes[i]
        var start = start_positions[i]
        var end = end_positions[i]

        play(star, start, end, func():
            completed_count += 1
            if completed_count == total_count:
                if on_complete.is_valid():
                    on_complete.call()
        )

        ## 错开启动时间（视觉层次）
        await get_tree().create_timer(0.1).timeout