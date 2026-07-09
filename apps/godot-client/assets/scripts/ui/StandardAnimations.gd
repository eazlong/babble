## StandardAnimations.gd
## 标准动画库 — 淡入淡出、滑入滑出、缩放、旋转
## 设计目标：统一动画函数，易于调用
## Godot 4.6, GDScript static typing

class_name StandardAnimations
extends RefCounted

## ============================================================
## 淡入淡出 (Fade)
## ============================================================

## 淡入实现
static func fade_in(target: CanvasItem, duration: float = UIAnimationPresets.FadeIn.DURATION) -> Tween:
    target.modulate.a = 0.0
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.FadeIn.TRANS)
    tween.set_ease(UIAnimationPresets.FadeIn.EASE)
    tween.tween_property(target, "modulate:a", 1.0, duration)

    return tween

## 淡出实现
static func fade_out(target: CanvasItem, duration: float = UIAnimationPresets.FadeOut.DURATION, callback: Callable = Callable()) -> Tween:
    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.FadeOut.TRANS)
    tween.set_ease(UIAnimationPresets.FadeOut.EASE)
    tween.tween_property(target, "modulate:a", 0.0, duration)

    if callback.is_valid():
        tween.tween_callback(callback)

    tween.tween_callback(func(): target.visible = false)

    return tween

## ============================================================
## 滑入滑出 (Slide)
## ============================================================

## 从右滑入
static func slide_in_from_right(target: Control, duration: float = UIAnimationPresets.PagePush.DURATION) -> Tween:
    var viewport_width = target.get_viewport().get_visible_rect().size.x
    target.position.x = viewport_width
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.PagePush.TRANS)
    tween.set_ease(UIAnimationPresets.PagePush.EASE)
    tween.tween_property(target, "position:x", 0.0, duration)

    return tween

## 向左滑出
static func slide_out_to_left(target: Control, duration: float = UIAnimationPresets.PagePop.DURATION, callback: Callable = Callable()) -> Tween:
    var viewport_width = target.get_viewport().get_visible_rect().size.x

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.PagePop.TRANS)
    tween.set_ease(UIAnimationPresets.PagePop.EASE)
    tween.tween_property(target, "position:x", -viewport_width, duration)

    if callback.is_valid():
        tween.tween_callback(callback)

    tween.tween_callback(func(): target.visible = false)

    return tween

## 从上滑入
static func slide_in_from_top(target: Control, duration: float = 0.25) -> Tween:
    var viewport_height = target.get_viewport().get_visible_rect().size.y
    target.position.y = -viewport_height
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(target, "position:y", 0.0, duration)

    return tween

## 向下滑出
static func slide_out_to_bottom(target: Control, duration: float = 0.2, callback: Callable = Callable()) -> Tween:
    var viewport_height = target.get_viewport().get_visible_rect().size.y

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_IN)
    tween.tween_property(target, "position:y", viewport_height, duration)

    if callback.is_valid():
        tween.tween_callback(callback)

    tween.tween_callback(func(): target.visible = false)

    return tween

## ============================================================
## 缩放动画 (Scale)
## ============================================================

## 弹出缩放 (带回弹)
static func scale_pop(target: Control, callback: Callable = Callable()) -> Tween:
    target.scale = Vector2(UIAnimationPresets.ScalePop.START_SCALE,
                           UIAnimationPresets.ScalePop.START_SCALE)
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.ScalePop.TRANS)
    tween.set_ease(UIAnimationPresets.ScalePop.EASE)

    # 先弹过头
    tween.tween_property(target, "scale",
        Vector2(UIAnimationPresets.ScalePop.OVERSHOOT, UIAnimationPresets.ScalePop.OVERSHOOT),
        UIAnimationPresets.ScalePop.DURATION * 0.6)

    # 再回到正常
    tween.tween_property(target, "scale",
        Vector2(UIAnimationPresets.ScalePop.END_SCALE, UIAnimationPresets.ScalePop.END_SCALE),
        UIAnimationPresets.ScalePop.DURATION * 0.4)

    if callback.is_valid():
        tween.tween_callback(callback)

    return tween

## 缩放淡入
static func scale_fade_in(target: Control, duration: float = 0.25) -> Tween:
    target.scale = Vector2(0.8, 0.8)
    target.modulate.a = 0.0
    target.visible = true

    var tween = target.create_tween()
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_BACK)
    tween.set_ease(Tween.EASE_OUT)

    tween.tween_property(target, "scale", Vector2(1.0, 1.0), duration)
    tween.tween_property(target, "modulate:a", 1.0, duration * 0.7)

    return tween

## 缩放淡出
static func scale_fade_out(target: Control, duration: float = 0.2, callback: Callable = Callable()) -> Tween:
    var tween = target.create_tween()
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_IN)

    tween.tween_property(target, "scale", Vector2(0.8, 0.8), duration)
    tween.tween_property(target, "modulate:a", 0.0, duration)

    tween.set_parallel(false)
    if callback.is_valid():
        tween.tween_callback(callback)
    tween.tween_callback(func(): target.visible = false)

    return tween

## 脉冲缩放 (用于提示)
static func pulse_scale(target: Control, scale_factor: float = 1.1, duration: float = 0.3) -> Tween:
    var original_scale = target.scale
    var target_scale = original_scale * scale_factor

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_IN_OUT)

    tween.tween_property(target, "scale", target_scale, duration * 0.5)
    tween.tween_property(target, "scale", original_scale, duration * 0.5)

    return tween

## ============================================================
## 旋转动画 (Rotate)
## ============================================================

## 旋转动画
static func rotate_to(target: Control, angle_degrees: float, duration: float = 0.5) -> Tween:
    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(target, "rotation_degrees", angle_degrees, duration)
    return tween

## 连续旋转 (用于加载)
static func rotate_continuous(target: Control, speed: float = 360.0) -> Tween:
    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_LINEAR)
    tween.tween_property(target, "rotation_degrees", speed, 1.0)
    tween.set_loops()  # 无限循环
    return tween

## 震动旋转
static func shake_rotation(target: Control, intensity: float = 10.0, duration: float = 0.3) -> Tween:
    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_ELASTIC)
    tween.set_ease(Tween.EASE_OUT)

    # 震动序列
    tween.tween_property(target, "rotation_degrees", intensity, duration * 0.25)
    tween.tween_property(target, "rotation_degrees", -intensity * 0.5, duration * 0.25)
    tween.tween_property(target, "rotation_degrees", intensity * 0.25, duration * 0.25)
    tween.tween_property(target, "rotation_degrees", 0.0, duration * 0.25)

    return tween

## ============================================================
## 组合动画
## ============================================================

## 弹性弹跳 (用于庆祝)
static func bounce_in(target: Control, duration: float = 0.6) -> Tween:
    target.scale = Vector2(0.0, 0.0)
    target.modulate.a = 0.0
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_ELASTIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.set_parallel(true)

    tween.tween_property(target, "scale", Vector2(1.2, 1.2), duration * 0.7)
    tween.tween_property(target, "modulate:a", 1.0, duration * 0.4)

    tween.set_parallel(false)
    tween.tween_property(target, "scale", Vector2(1.0, 1.0), duration * 0.3)

    return tween

## 震动效果 (用于错误提示)
static func shake_position(target: Control, intensity: float = 10.0, duration: float = 0.4) -> Tween:
    var original_pos = target.position

    var tween = target.create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_OUT)

    # 左右震动3次
    for i in range(3):
        tween.tween_property(target, "position:x", original_pos.x + intensity, duration * 0.1)
        tween.tween_property(target, "position:x", original_pos.x - intensity, duration * 0.1)

    tween.tween_property(target, "position", original_pos, duration * 0.1)

    return tween

## ============================================================
## 工具函数
## ============================================================

## 停止所有动画
static func stop_all_animations(target: Control) -> void:
    # 停止所有Tween
    # 注意：需要通过UITweenManager管理
    pass