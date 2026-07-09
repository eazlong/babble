## PerformanceMonitor.gd
## 性能监控与降级触发系统
## 监控FPS、Draw Calls、内存使用，自动触发性能降级策略

class_name PerformanceMonitor
extends Node

## ============================================================
## 性能预算配置
## ============================================================

## FPS阈值 (降级触发线)
const FPS_FULL_THRESHOLD: float = 55.0        # FPS>=55: 全特效
const FPS_REDUCED_THRESHOLD: float = 45.0     # FPS>=45: 减少特效
const FPS_MINIMAL_THRESHOLD: float = 30.0     # FPS>=30: 最小特效
const FPS_CRITICAL_THRESHOLD: float = 30.0    # FPS<30: 禁用特效

## 降级级别枚举
enum DegradationLevel {
    NONE = 0,              # 全特效 (桌面默认)
    LEVEL_1 = 1,           # 减少粒子 (FPS<55)
    LEVEL_2 = 2,           # 禁用Shader (FPS<45)
    LEVEL_3 = 3,           # 简化Tween (FPS<30)
    DISABLED = 4           # 禁用所有 (紧急)
}

## ============================================================
## 状态变量
## ============================================================

## 当前性能指标
var current_fps: float = 60.0
var current_draw_calls: int = 0
var current_memory_mb: float = 0.0

## 当前降级级别
var current_degradation_level: DegradationLevel = DegradationLevel.NONE

## FPS采样缓冲区 (用于平滑处理)
var fps_buffer: Array[float] = []
const FPS_BUFFER_SIZE: int = 10

## ============================================================
## 信号定义
## ============================================================

signal degradation_triggered(level: DegradationLevel)
signal performance_recovered(level: DegradationLevel)
signal fps_warning(fps: float)
signal memory_warning(memory_mb: float)

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
    # 初始化FPS缓冲区
    fps_buffer.resize(FPS_BUFFER_SIZE)
    for i in range(FPS_BUFFER_SIZE):
        fps_buffer[i] = 60.0

    # 连接VFXManager降级响应 (如果已存在)
    if has_node("/root/VFXManager"):
        degradation_triggered.connect(_on_degradation_triggered)

## ============================================================
## 主循环 - 监控性能
## ============================================================

func _process(delta: float) -> void:
    # 采集当前FPS
    _update_fps()

    # 采集Draw Calls
    _update_draw_calls()

    # 采集内存使用
    _update_memory()

    # 检查性能并触发降级
    _check_performance()

## ============================================================
## FPS采样与平滑处理
## ============================================================

func _update_fps() -> void:
    # 获取当前帧率
    current_fps = Engine.get_frames_per_second()

    # 添加到缓冲区 (滑动窗口)
    fps_buffer.push_back(current_fps)
    if fps_buffer.size() > FPS_BUFFER_SIZE:
        fps_buffer.pop_front()

    # 计算平滑FPS (平均值)
    var smoothed_fps: float = 0.0
    for fps in fps_buffer:
        smoothed_fps += fps
    smoothed_fps /= fps_buffer.size()

    # 使用平滑FPS进行决策
    current_fps = smoothed_fps

## ============================================================
## Draw Calls监控
## ============================================================

func _update_draw_calls() -> void:
    # 获取当前帧Draw Calls
    current_draw_calls = RenderingServer.get_rendering_info(
        RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
    )

## ============================================================
## 内存监控
## ============================================================

func _update_memory() -> void:
    # 获取静态内存使用 (字节)
    var memory_bytes = OS.get_static_memory_usage()

    # 转换为MB
    current_memory_mb = memory_bytes / (1024.0 * 1024.0)

## ============================================================
## 性能检查与降级决策
## ============================================================

func _check_performance() -> void:
    # 计算新的降级级别
    var new_level = _calculate_degradation_level()

    # 如果降级级别发生变化
    if new_level != current_degradation_level:
        # 判断是降级还是恢复
        if new_level > current_degradation_level:
            # 性能下降，触发降级
            _trigger_degradation(new_level)
        else:
            # 性能恢复
            _trigger_recovery(new_level)

## ============================================================
## 计算降级级别
## ============================================================

func _calculate_degradation_level() -> DegradationLevel:
    # 根据FPS阈值判断
    if current_fps >= FPS_FULL_THRESHOLD:
        return DegradationLevel.NONE
    elif current_fps >= FPS_REDUCED_THRESHOLD:
        return DegradationLevel.LEVEL_1
    elif current_fps >= FPS_MINIMAL_THRESHOLD:
        return DegradationLevel.LEVEL_2
    elif current_fps > 0.0:  # FPS<30 但 > 0
        return DegradationLevel.LEVEL_3
    else:
        return DegradationLevel.DISABLED

## ============================================================
## 触发降级
## ============================================================

func _trigger_degradation(new_level: DegradationLevel) -> void:
    var old_level = current_degradation_level
    current_degradation_level = new_level

    # 发出降级信号
    degradation_triggered.emit(new_level)

    # Debug输出
    if OS.is_debug_build():
        var level_name = _get_level_name(new_level)
        print("[PerformanceMonitor] 性能降级: %s → %s (FPS=%.1f)" % [
            _get_level_name(old_level), level_name, current_fps
        ])

    # FPS警告 (如果FPS<45)
    if current_fps < FPS_REDUCED_THRESHOLD:
        fps_warning.emit(current_fps)

## ============================================================
## 触发恢复
## ============================================================

func _trigger_recovery(new_level: DegradationLevel) -> void:
    var old_level = current_degradation_level
    current_degradation_level = new_level

    # 发出恢复信号
    performance_recovered.emit(new_level)

    # Debug输出
    if OS.is_debug_build():
        var level_name = _get_level_name(new_level)
        print("[PerformanceMonitor] 性能恢复: %s → %s (FPS=%.1f)" % [
            _get_level_name(old_level), level_name, current_fps
        ])

## ============================================================
## 降级响应回调 (连接VFXManager)
## ============================================================

func _on_degradation_triggered(level: DegradationLevel) -> void:
    # 通知VFXManager调整特效
    if has_node("/root/VFXManager"):
        var vfx_manager = get_node("/root/VFXManager")
        vfx_manager.set_degradation_level(level)

## ============================================================
## 辅助函数
## ============================================================

## 获取降级级别名称
func _get_level_name(level: DegradationLevel) -> String:
    match level:
        DegradationLevel.NONE:
            return "NONE (全特效)"
        DegradationLevel.LEVEL_1:
            return "LEVEL_1 (减少粒子)"
        DegradationLevel.LEVEL_2:
            return "LEVEL_2 (禁用Shader)"
        DegradationLevel.LEVEL_3:
            return "LEVEL_3 (简化Tween)"
        DegradationLevel.DISABLED:
            return "DISABLED (紧急)"
    return "UNKNOWN"

## ============================================================
## 公共接口 - 获取性能数据
## ============================================================

## 获取当前FPS
func get_fps() -> float:
    return current_fps

## 获取当前降级级别
func get_degradation_level() -> DegradationLevel:
    return current_degradation_level

## 获取性能报告 (用于DebugOverlay)
func get_performance_report() -> Dictionary:
    return {
        "fps": current_fps,
        "draw_calls": current_draw_calls,
        "memory_mb": current_memory_mb,
        "degradation_level": current_degradation_level,
        "degradation_name": _get_level_name(current_degradation_level)
    }

## 强制设置降级级别 (用于测试)
func force_degradation(level: DegradationLevel) -> void:
    current_degradation_level = level
    degradation_triggered.emit(level)