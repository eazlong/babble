## ShaderManager.gd
## Shader管理器 — Shader材质池管理 + 降级策略
## 设计目标：统一Shader管理，性能降级，材质复用
## Godot 4.6, GDScript static typing

class_name ShaderManager
extends Node

## ============================================================
## Shader配置
## ============================================================

## Shader路径映射
const SHADER_PATHS: Dictionary = {
    "spirit_glow": "res://assets/resources/shaders/spirit/spirit_glow.gdshader",
    "magic_burst": "res://assets/resources/shaders/effects/magic_burst.gdshader",
    "transition_wipe": "res://assets/resources/shaders/effects/transition_wipe.gdshader"
}

## Shader性能预算 (ms/帧)
const SHADER_BUDGET: Dictionary = {
    "spirit_glow": 2.0,
    "magic_burst": 2.5,
    "transition_wipe": 1.0
}

## Shader复杂度等级
enum ShaderComplexity {
    LOW,      # 仅fragment
    MEDIUM,   # fragment + vertex
    HIGH      # 复杂数学运算
}

## Shader复杂度映射
const SHADER_COMPLEXITY: Dictionary = {
    "spirit_glow": ShaderComplexity.MEDIUM,
    "magic_burst": ShaderComplexity.MEDIUM,
    "transition_wipe": ShaderComplexity.LOW
}

## ============================================================
## Shader材质池
## ============================================================

## Shader材质缓存
var shader_cache: Dictionary = {}  # String -> Shader

## ShaderMaterial实例池
var material_pool: Dictionary = {}  # String -> Array[ShaderMaterial]

## 材质池初始大小
const POOL_INITIAL_SIZE: int = 5

## 当前降级级别
var current_degradation_level: int = 0  # PerformanceMonitor.DegradationLevel.NONE

## ============================================================
## 信号定义
## ============================================================

signal shader_loaded(shader_name: String)
signal shader_failed(shader_name: String, error: String)
signal degradation_applied(level: int)
signal material_created(shader_name: String)

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
    # 预加载所有Shader
    _preload_all_shaders()

    # 预热材质池
    _prewarm_material_pools()

    # 连接PerformanceMonitor降级信号
    if has_node("/root/PerformanceMonitor"):
        var perf_monitor = get_node("/root/PerformanceMonitor")
        perf_monitor.degradation_triggered.connect(_on_degradation_triggered)

## ============================================================
## Shader预加载
## ============================================================

func _preload_all_shaders() -> void:
    for shader_name in SHADER_PATHS.keys():
        var shader_path = SHADER_PATHS[shader_name]

        if ResourceLoader.exists(shader_path):
            var shader = load(shader_path)
            shader_cache[shader_name] = shader
            shader_loaded.emit(shader_name)
        else:
            shader_failed.emit(shader_name, "Shader file not found")

## ============================================================
## 材质池预热
## ============================================================

func _prewarm_material_pools() -> void:
    for shader_name in shader_cache.keys():
        var pool: Array[ShaderMaterial] = []

        for i in range(POOL_INITIAL_SIZE):
            var material = _create_shader_material(shader_name)
            pool.append(material)

        material_pool[shader_name] = pool

## ============================================================
## ShaderMaterial创建
## ============================================================

func _create_shader_material(shader_name: String) -> ShaderMaterial:
    if not shader_cache.has(shader_name):
        return null

    var shader: Shader = shader_cache[shader_name]
    var material = ShaderMaterial.new()
    material.shader = shader

    # 设置默认参数
    _set_default_parameters(material, shader_name)

    material_created.emit(shader_name)
    return material

## ============================================================
## 默认参数设置
## ============================================================

func _set_default_parameters(material: ShaderMaterial, shader_name: String) -> void:
    match shader_name:
        "spirit_glow":
            material.set_shader_parameter("glow_color", Color(1.0, 0.9, 0.4, 1.0))
            material.set_shader_parameter("glow_intensity", 1.0)
            material.set_shader_parameter("pulse_speed", 1.0)
            material.set_shader_parameter("rim_width", 0.2)

        "magic_burst":
            material.set_shader_parameter("burst_color", Color(0.8, 0.4, 1.0, 0.8))
            material.set_shader_parameter("intensity", 1.0)
            material.set_shader_parameter("duration", 1.0)
            material.set_shader_parameter("progress", 0.0)

        "transition_wipe":
            material.set_shader_parameter("progress", 0.0)
            material.set_shader_parameter("wipe_direction", Vector2(1.0, 0.0))
            material.set_shader_parameter("wipe_color", Color(0.2, 0.2, 0.3, 1.0))
            material.set_shader_parameter("radial_mode", false)
            material.set_shader_parameter("smoothness", 0.05)

## ============================================================
## 获取ShaderMaterial (从池中)
## ============================================================

func get_material(shader_name: String) -> ShaderMaterial:
    # 检查降级策略
    if current_degradation_level >= 2:  # LEVEL_2: 禁用Shader
        return null

    # 从池中获取
    if material_pool.has(shader_name):
        var pool: Array = material_pool[shader_name]
        if pool.size() > 0:
            return pool.pop_back()

    # 池已耗尽，创建新材质
    var material = _create_shader_material(shader_name)
    return material

## ============================================================
## 回收ShaderMaterial
## ============================================================

func recycle_material(shader_name: String, material: ShaderMaterial) -> void:
    # 重置参数
    _set_default_parameters(material, shader_name)

    # 返回池中
    if material_pool.has(shader_name):
        var pool: Array = material_pool[shader_name]
        pool.append(material)

## ============================================================
## Shader应用
## ============================================================

## 应用Shader到Sprite
func apply_shader(sprite: Sprite2D, shader_name: String) -> ShaderMaterial:
    var material = get_material(shader_name)

    if material != null:
        sprite.material = material

    return material

## 应用Shader并动画化progress参数
func apply_shader_with_animation(sprite: Sprite2D, shader_name: String, duration: float) -> ShaderMaterial:
    var material = apply_shader(sprite, shader_name)

    if material == null:
        return null

    # 动画化progress参数 (0.0 → 1.0)
    if shader_name == "magic_burst" or shader_name == "transition_wipe":
        animate_shader_parameter(material, "progress", 0.0, 1.0, duration)

    return material

## ============================================================
## Shader参数动画
## ============================================================

func animate_shader_parameter(material: ShaderMaterial, param_name: String, from: float, to: float, duration: float) -> void:
    # 检查降级策略
    if current_degradation_level >= 2:
        return

    material.set_shader_parameter(param_name, from)

    var tween = create_tween()
    tween.tween_method(
        func(value: float): material.set_shader_parameter(param_name, value),
        from, to, duration
    )

## ============================================================
## 降级策略执行
## ============================================================

func _on_degradation_triggered(level: int) -> void:
    current_degradation_level = level

    # 执行降级措施
    match level:
        2:  # LEVEL_2: 禁用Shader
            _disable_all_shaders()

    degradation_applied.emit(level)

func _disable_all_shaders() -> void:
    # 清空材质池
    for shader_name in material_pool.keys():
        var pool: Array = material_pool[shader_name]
        for material in pool:
            # ShaderMaterial会在节点释放时自动清理
            pass
        pool.clear()

## ============================================================
## Shader性能预算查询
## ============================================================

func get_shader_budget(shader_name: String) -> float:
    return SHADER_BUDGET.get(shader_name, 0.0)

func get_shader_complexity(shader_name: String) -> ShaderComplexity:
    return SHADER_COMPLEXITY.get(shader_name, ShaderComplexity.LOW)

## ============================================================
## 公共接口
## ============================================================

## 列出所有可用Shader
func list_available_shaders() -> Array[String]:
    var available: Array[String] = []
    for shader_name in shader_cache.keys():
        available.append(shader_name)
    return available

## 检查Shader是否可用
func is_shader_available(shader_name: String) -> bool:
    return shader_cache.has(shader_name)

## 获取材质池状态
func get_pool_status() -> Dictionary:
    var status = {}
    for shader_name in material_pool.keys():
        var pool: Array = material_pool[shader_name]
        status[shader_name] = {
            "available": pool.size(),
            "total": POOL_INITIAL_SIZE
        }
    return status