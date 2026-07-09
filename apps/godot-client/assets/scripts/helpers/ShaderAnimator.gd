## ShaderAnimator.gd
## Shader动画辅助类 — Shader参数动画控制
## 设计目标：简化Shader参数动画，提供链式调用接口
## Godot 4.6, GDScript static typing

class_name ShaderAnimator
extends RefCounted

## ============================================================
## ShaderAnimator状态
## ============================================================

## 目标节点
var _target: Node2D

## ShaderMaterial引用
var _material: ShaderMaterial

## 活跃的Tween引用 (防止GC)
var _active_tweens: Dictionary = {}  # String -> Tween

## ============================================================
## 初始化
## ============================================================

func _init(target: Node2D) -> void:
    _target = target
    if target.material and target.material is ShaderMaterial:
        _material = target.material

## ============================================================
## 设置ShaderMaterial
## ============================================================

func set_material(material: ShaderMaterial) -> ShaderAnimator:
    _material = material
    _target.material = material
    return self  # 链式调用

## ============================================================
## 参数设置 (立即生效)
## ============================================================

func set_param(param_name: String, value: Variant) -> ShaderAnimator:
    if _material == null:
        push_warning("[ShaderAnimator] Material未设置")
        return self

    _material.set_shader_parameter(param_name, value)
    return self

## ============================================================
## 参数动画 (Tween)
## ============================================================

## 动画化float参数
func animate_float(param_name: String, from: float, to: float, duration: float) -> ShaderAnimator:
    if _material == null:
        return self

    # 设置初始值
    _material.set_shader_parameter(param_name, from)

    # 创建Tween
    var tween = _target.create_tween()
    tween.tween_method(
        func(value: float): _material.set_shader_parameter(param_name, value),
        from, to, duration
    )

    # 保存Tween引用
    _active_tweens[param_name] = tween

    return self

## 动画化Color参数
func animate_color(param_name: String, from: Color, to: Color, duration: float) -> ShaderAnimator:
    if _material == null:
        return self

    _material.set_shader_parameter(param_name, from)

    var tween = _target.create_tween()
    tween.tween_method(
        func(value: Color): _material.set_shader_parameter(param_name, value),
        from, to, duration
    )

    _active_tweens[param_name] = tween
    return self

## 动画化Vector2参数
func animate_vector2(param_name: String, from: Vector2, to: Vector2, duration: float) -> ShaderAnimator:
    if _material == null:
        return self

    _material.set_shader_parameter(param_name, from)

    var tween = _target.create_tween()
    tween.tween_method(
        func(value: Vector2): _material.set_shader_parameter(param_name, value),
        from, to, duration
    )

    _active_tweens[param_name] = tween
    return self

## ============================================================
## 动画配置 (Trans/Ease)
## ============================================================

func set_trans(trans_type: Tween.TransitionType) -> ShaderAnimator:
    # 应用到最后创建的Tween
    if _active_tweens.size() > 0:
        var last_key = _active_tweens.keys().back()
        var tween: Tween = _active_tweens[last_key]
        tween.set_trans(trans_type)
    return self

func set_ease(ease_type: Tween.EaseType) -> ShaderAnimator:
    if _active_tweens.size() > 0:
        var last_key = _active_tweens.keys().back()
        var tween: Tween = _active_tweens[last_key]
        tween.set_ease(ease_type)
    return self

## ============================================================
## 回调绑定
## ============================================================

func on_complete(callback: Callable) -> ShaderAnimator:
    if _active_tweens.size() > 0:
        var last_key = _active_tweens.keys().back()
        var tween: Tween = _active_tweens[last_key]
        tween.tween_callback(callback)
    return self

## ============================================================
## 常用Shader动画预设
## ============================================================

## spirit_glow脉冲动画 (自动循环)
func pulse_glow(speed: float = 1.0, intensity_range: Vector2 = Vector2(0.5, 1.5)) -> ShaderAnimator:
    # 设置pulse_speed
    set_param("pulse_speed", speed)

    # 启用pulse
    set_param("enable_pulse", true)

    return self

## magic_burst爆发动画 (progress: 0→1)
func burst(duration: float = 1.0) -> ShaderAnimator:
    animate_float("progress", 0.0, 1.0, duration)
    set_trans(Tween.TRANS_CUBIC)
    set_ease(Tween.EASE_OUT)
    return self

## transition_wipe过渡动画 (progress: 0→1)
func wipe(duration: float = 0.3, direction: Vector2 = Vector2(1.0, 0.0)) -> ShaderAnimator:
    set_param("wipe_direction", direction)
    animate_float("progress", 0.0, 1.0, duration)
    set_trans(Tween.TRANS_CUBIC)
    set_ease(Tween.EASE_IN_OUT)
    return self

## ============================================================
## Tween控制
## ============================================================

## 停止指定参数动画
func stop_param(param_name: String) -> void:
    if _active_tweens.has(param_name):
        var tween: Tween = _active_tweens[param_name]
        if tween and tween.is_valid():
            tween.kill()
        _active_tweens.erase(param_name)

## 停止所有动画
func stop_all() -> void:
    for param_name in _active_tweens.keys():
        var tween: Tween = _active_tweens[param_name]
        if tween and tween.is_valid():
            tween.kill()
    _active_tweens.clear()

## 暂停所有动画
func pause_all() -> void:
    for tween in _active_tweens.values():
        if tween and tween.is_valid():
            tween.pause()

## 继续所有动画
func resume_all() -> void:
    for tween in _active_tweens.values():
        if tween and tween.is_valid():
            tween.play()

## ============================================================
## 状态查询
## ============================================================

## 是否有活跃动画
func has_active_animations() -> bool:
    return _active_tweens.size() > 0

## 获取活跃动画数量
func get_active_count() -> int:
    return _active_tweens.size()

## 获取Material引用
func get_material() -> ShaderMaterial:
    return _material

## ============================================================
## 静态工厂方法 (便捷创建)
## ============================================================

static func create(target: Node2D) -> ShaderAnimator:
    return ShaderAnimator.new(target)

static func create_with_shader(target: Node2D, shader_name: String) -> ShaderAnimator:
    var animator = ShaderAnimator.new(target)

    # 从ShaderManager获取材质
    if has_node("/root/ShaderManager"):
        var shader_mgr = get_node("/root/ShaderManager")
        var material = shader_mgr.get_material(shader_name)
        if material:
            animator.set_material(material)

    return animator