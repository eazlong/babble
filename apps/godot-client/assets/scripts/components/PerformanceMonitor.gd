## PerformanceMonitor.gd
## 性能监控组件 — 监控 FPS 并触发性能降级策略
## 集成到 VFXManager 实现自动性能调节
extends Node

# ── Signals ────────────────────────────────────────────────────────────────
signal fps_updated(fps: float)
signal performance_warning(level: int, message: String)

# ── Configuration ─────────────────────────────────────────────────────────
@export var update_interval_ms: int = 500
@export var fps_threshold_critical: float = 30.0
@export var fps_threshold_warning: float = 45.0
@export var fps_threshold_notice: float = 55.0

# ── Internal State ────────────────────────────────────────────────────────
var _fps_history: Array[float] = []
var _last_update_time: int = 0
var _frame_count: int = 0

const HISTORY_SIZE: int = 10
const MOVING_AVERAGE: bool = true

# ── Public Properties (Read-only) ────────────────────────────────────────
var current_fps: float = 60.0
var average_fps: float = 60.0
var min_fps: float = 60.0
var max_fps: float = 60.0

# ── Lifecycle ────────────────────────────────────────────────────────────
func _ready() -> void:
	_last_update_time = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	_frame_count += 1

	var now: int = Time.get_ticks_msec()
	var elapsed: int = now - _last_update_time

	if elapsed >= update_interval_ms:
		_calculate_fps(elapsed)
		_last_update_time = now
		_frame_count = 0

# ── FPS Calculation ──────────────────────────────────────────────────────
func _calculate_fps(elapsed_ms: int) -> void:
	if elapsed_ms <= 0:
		return

	current_fps = float(_frame_count) / (elapsed_ms / 1000.0)

	_fps_history.append(current_fps)
	if _fps_history.size() > HISTORY_SIZE:
		_fps_history.remove_at(0)

	if MOVING_AVERAGE and _fps_history.size() > 0:
		var total: float = 0.0
		min_fps = _fps_history[0]
		max_fps = _fps_history[0]

		for fps in _fps_history:
			total += fps
			if fps < min_fps:
				min_fps = fps
			if fps > max_fps:
				max_fps = fps

		average_fps = total / _fps_history.size()
	else:
		average_fps = current_fps
		min_fps = mini(min_fps, current_fps)
		max_fps = maxi(max_fps, current_fps)

	fps_updated.emit(current_fps)
	_check_performance_warnings()

# ── Performance Warning System ────────────────────────────────────────────
func _check_performance_warnings() -> void:
	if current_fps < fps_threshold_critical:
		performance_warning.emit(3, "Critical: FPS below %.0f (current: %.1f)" % [fps_threshold_critical, current_fps])
	elif current_fps < fps_threshold_warning:
		performance_warning.emit(2, "Warning: FPS below %.0f (current: %.1f)" % [fps_threshold_warning, current_fps])
	elif current_fps < fps_threshold_notice:
		performance_warning.emit(1, "Notice: FPS below %.0f (current: %.1f)" % [fps_threshold_notice, current_fps])

# ── Public API ───────────────────────────────────────────────────────────
func get_fps_stats() -> Dictionary:
	return {
		"current": current_fps,
		"average": average_fps,
		"min": min_fps,
		"max": max_fps,
		"history_size": _fps_history.size()
	}

func reset_stats() -> void:
	_fps_history.clear()
	min_fps = 60.0
	max_fps = 60.0
	average_fps = 60.0
