## UITweenManager.gd
## Tween生命周期管理 — 确保并发数量限制和内存安全
## 设计目标：50并发限制、防止GC、类别优先级管理
## Godot 4.6, GDScript static typing

extends Node

## ============================================================
## 并发限制配置
## ============================================================

## 最大并发Tween数量 (性能预算)
const MAX_ACTIVE_TWEENS: int = 50

## ============================================================
## Tween注册表
## ============================================================

## 活跃Tween字典
var _active_tweens: Dictionary = {}      # String -> Tween

## Tween计数器
var _tween_counter: int = 0

## ============================================================
## 信号定义
## ============================================================

signal tween_started(tween_id: String)
signal tween_completed(tween_id: String)
signal tween_killed(tween_id: String)
signal pool_exhausted()

## ============================================================
## 注册Tween
## ============================================================

func register_tween(category: String, tween: Tween) -> String:
	# 检查并发限制
	if _active_tweens.size() >= MAX_ACTIVE_TWEENS:
		push_warning("[UITweenManager] Tween池已满 (%d/%d)，拒绝新动画" % [_active_tweens.size(), MAX_ACTIVE_TWEENS])
		pool_exhausted.emit()
		# 杀死最旧的非关键Tween
		_kill_oldest_non_critical()

	# 生成唯一ID
	var tween_id = "%s_%d_%d" % [category, Time.get_ticks_msec(), _tween_counter]
	_tween_counter += 1

	# 注册到字典
	_active_tweens[tween_id] = tween

	# 绑定完成回调
	tween.finished.connect(_on_tween_finished.bind(tween_id))

	# 发出信号
	tween_started.emit(tween_id)

	return tween_id

## ============================================================
## 杀死指定Tween
## ============================================================

func kill_tween(tween_id: String) -> void:
	if not _active_tweens.has(tween_id):
		return

	var tween: Tween = _active_tweens[tween_id]
	if tween and tween.is_valid():
		tween.kill()

	_active_tweens.erase(tween_id)
	tween_killed.emit(tween_id)

## ============================================================
## 杀死某类别的所有Tween
## ============================================================

func kill_category(category: String) -> void:
	var to_kill: Array[String] = []

	for tween_id in _active_tweens.keys():
		if tween_id.begins_with(category + "_"):
			to_kill.append(tween_id)

	for tween_id in to_kill:
		kill_tween(tween_id)

## ============================================================
## 杀死所有Tween (场景切换用)
## ============================================================

func kill_all() -> void:
	for tween_id in _active_tweens.keys():
		var tween: Tween = _active_tweens[tween_id]
		if tween and tween.is_valid():
			tween.kill()

	_active_tweens.clear()
	tween_killed.emit("all")

## ============================================================
## 获取活跃Tween数量
## ============================================================

func get_active_count() -> int:
	return _active_tweens.size()

## ============================================================
## Tween完成回调
## ============================================================

func _on_tween_finished(tween_id: String) -> void:
	if _active_tweens.has(tween_id):
		_active_tweens.erase(tween_id)
		tween_completed.emit(tween_id)

## ============================================================
## 杀死最旧的非关键Tween
## ============================================================

func _kill_oldest_non_critical() -> void:
	# 定义关键类别 (这些不应该被杀死)
	var critical_categories = ["scene_transition", "dialogue"]

	for tween_id in _active_tweens.keys():
		var is_critical = false
		for cat in critical_categories:
			if tween_id.begins_with(cat + "_"):
				is_critical = true
				break

		if not is_critical:
			kill_tween(tween_id)
			return

## ============================================================
## 清理无效Tween (定期调用)
## ============================================================

func cleanup() -> void:
	var invalid: Array[String] = []

	for tween_id in _active_tweens.keys():
		var tween: Tween = _active_tweens[tween_id]
		if not tween or not tween.is_valid():
			invalid.append(tween_id)

	for tween_id in invalid:
		_active_tweens.erase(tween_id)

## ============================================================
## 并发限制类别配置
## ============================================================

static func get_concurrency_limits() -> Dictionary:
	return {
		"scene_transition": {"max": 1, "priority": "高", "desc": "必须保证"},
		"dialogue": {"max": 3, "priority": "高", "desc": "气泡+文字+头像"},
		"ui_feedback": {"max": 10, "priority": "中", "desc": "按钮点击等"},
		"vfx": {"max": 20, "priority": "中", "desc": "星星飞行等"},
		"ambient": {"max": 16, "priority": "低", "desc": "可降级"},
		"total": {"max": 50, "priority": "硬限制", "desc": ""}
	}

## ============================================================
## 状态报告
## ============================================================

func get_status_report() -> Dictionary:
	cleanup()  # 先清理无效Tween

	var report = {
		"active_count": _active_tweens.size(),
		"max_limit": MAX_ACTIVE_TWEENS,
		"pool_usage_percent": (_active_tweens.size() / MAX_ACTIVE_TWEENS) * 100.0,
		"categories": {}
	}

	# 按类别统计
	for tween_id in _active_tweens.keys():
		var category = tween_id.split("_")[0]
		if not report["categories"].has(category):
			report["categories"][category] = 0
		report["categories"][category] += 1

	return report
