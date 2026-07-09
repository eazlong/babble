## SessionTimer.gd
## 会话计时器 — 学习时长统计 + 休息提醒
## 设计目标：30分钟自动提醒休息，显示倒计时进度，支持家长控制台同步
## Godot 4.6, GDScript static typing

class_name SessionTimer
extends Control

## ============================================================
## 配置参数
## ============================================================

## 学习时长上限（30分钟）
const SESSION_DURATION_MINUTES: int = 30

## 休息提醒间隔（10分钟）
const BREAK_REMINDER_INTERVAL: int = 10

## ============================================================
## Node引用
## ============================================================

@onready var timer_display: Label = $TimerDisplay
@onready var progress_circle: ProgressBar = $ProgressCircle
@onready var reminder_popup: PanelContainer = $ReminderPopup

## ============================================================
## 计时状态
## ============================================================

## 会话开始时间
var _session_start_time: float = 0.0

## 当前已学习时长（分钟）
var _current_duration: float = 0.0

## 是否显示提醒
var _reminder_active: bool = false

## 计时Timer
var _session_timer: Timer

## ============================================================
## 信号定义
## ============================================================

signal session_started()
signal session_ended(duration_minutes: float)
signal break_reminder_triggered()
signal session_limit_reached()

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
	_create_session_timer()
	visible = false

func _create_session_timer() -> void:
	_session_timer = Timer.new()
	_session_timer.one_shot = false
	_session_timer.wait_time = 60.0  # 每分钟更新
	_session_timer.timeout.connect(_on_minute_tick)
	add_child(_session_timer)

## ============================================================
## 开始会话计时
## ============================================================

func start_session() -> void:
	_session_start_time = Time.get_unix_time_from_system()
	_current_duration = 0.0
	_session_timer.start()

	visible = true
	session_started.emit()

	_update_display()

## ============================================================
## 结束会话计时
## ============================================================

func end_session() -> void:
	_session_timer.stop()

	# 记录总时长
	var total_minutes = _current_duration

	# 同步到家长控制台（如果有）
	_sync_to_parent_dashboard(total_minutes)

	session_ended.emit(total_minutes)

	visible = false

## ============================================================
## 每分钟更新回调
## ============================================================

func _on_minute_tick() -> void:
	_current_duration += 1.0

	_update_display()

	# 检查休息提醒
	if int(_current_duration) % BREAK_REMINDER_INTERVAL == 0:
		_trigger_break_reminder()

	# 检查时长上限
	if _current_duration >= SESSION_DURATION_MINUTES:
		_trigger_session_limit()

## ============================================================
## 更新显示
## ============================================================

func _update_display() -> void:
	if timer_display:
		# 显示已学习时长
		var minutes = int(_current_duration)
		timer_display.text = str(minutes) + "分钟"

	if progress_circle:
		# 显示进度（相对于30分钟）
		var progress_percent = (_current_duration / SESSION_DURATION_MINUTES) * 100.0
		progress_circle.value = progress_percent

## ============================================================
## 休息提醒
## ============================================================

func _trigger_break_reminder() -> void:
	if _reminder_active:
		return

	_reminder_active = true

	if reminder_popup:
		reminder_popup.visible = true
		reminder_popup.modulate.a = 0.0

		# 弹出动画
		var tween = reminder_popup.create_tween()
		tween.set_trans(Tween.TRANS_BACK)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(reminder_popup, "modulate:a", 1.0, 0.3)
		tween.tween_property(reminder_popup, "scale", Vector2(1.15, 1.15), 0.3)
		tween.tween_property(reminder_popup, "scale", Vector2(1.0, 1.0), 0.2)

		# 3秒后自动隐藏
		tween.tween_interval(3.0)
		tween.tween_property(reminder_popup, "modulate:a", 0.0, 0.5)
		tween.tween_callback(func():
			reminder_popup.visible = false
			_reminder_active = false
		)

	break_reminder_triggered.emit()

## ============================================================
## 时长上限提醒
## ============================================================

func _trigger_session_limit() -> void:
	# 停止计时
	_session_timer.stop()

	# 显示时长上限提醒
	if reminder_popup:
		reminder_popup.visible = true

		# 更新提醒文本
		var reminder_label: Label = reminder_popup.get_node_or_null("ReminderLabel")
		if reminder_label:
			reminder_label.text = "今日学习时长已达上限！请休息一下。"

	# 发出信号
	session_limit_reached.emit()

## ============================================================
## 同步到家长控制台
## ============================================================

func _sync_to_parent_dashboard(duration_minutes: float) -> void:
	# 发送HTTP请求到家长控制台API
	# POST /api/v1/parent/dashboard/session-logs
	# Body: {child_id, duration_minutes, timestamp}

	# 实际实现需要HTTPClient
	# _send_session_log(duration_minutes)
	pass

## ============================================================
## 获取当前时长
## ============================================================

func get_current_duration() -> float:
	return _current_duration

## ============================================================
## 重置计时器（家长控制台调用）
## ============================================================

func reset_session() -> void:
	_session_timer.stop()
	_current_duration = 0.0
	_update_display()
	visible = false