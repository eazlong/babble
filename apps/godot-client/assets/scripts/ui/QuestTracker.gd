## QuestTracker.gd
## 任务追踪组件 — 实时显示当前任务进度
## 设计目标：清晰的进度可视化，支持多任务列表
## Godot 4.6, GDScript static typing

class_name QuestTracker
extends Control

## ============================================================
## 配置参数
## ============================================================

## 最大显示任务数量
const MAX_DISPLAY_QUESTS: int = 3

## ============================================================
## Node引用
## ============================================================

@onready var quest_list_container: VBoxContainer = $QuestListContainer

## ============================================================
## 任务数据结构
## ============================================================

## 任务条目字典 {quest_id: {name, progress, total, is_completed}}
var quest_entries: Dictionary = {}

## ============================================================
## 外部系统引用
## ============================================================

var _quest_websocket: QuestWebSocket

## ============================================================
## 信号定义
## ============================================================

signal quest_clicked(quest_id: String)
signal quest_completed(quest_id: String)

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
	# 获取QuestWebSocket引用
	_quest_websocket = get_node_or_null("/root/QuestWebSocket")

	# 连接QuestWebSocket信号
	if _quest_websocket:
		if _quest_websocket.has_signal("quest_updated"):
			_quest_websocket.quest_updated.connect(_on_quest_updated)
		_quest_websocket.quest_completed.connect(_on_quest_completed_signal)

	visible = false  # 默认隐藏

## ============================================================
## 更新任务列表
## ============================================================

func update_quest_list(quests: Array) -> void:
	# 清空容器
	if quest_list_container:
		for child in quest_list_container.get_children():
			child.queue_free()

	# 显示前MAX_DISPLAY_QUESTS个任务
	var display_count = min(quests.size(), MAX_DISPLAY_QUESTS)

	for i in range(display_count):
		var quest_data = quests[i]
		_create_quest_entry(quest_data)

	visible = true

## ============================================================
## 创建任务条目
## ============================================================

func _create_quest_entry(quest_data: Dictionary) -> void:
	if not quest_list_container:
		return

	var quest_id = quest_data.get("quest_id", "")
	var quest_name = quest_data.get("name", "任务")
	var progress = quest_data.get("progress", 0)
	var total = quest_data.get("total", 1)
	var is_completed = quest_data.get("is_completed", false)

	# 创建条目UI
	var entry_container = HBoxContainer.new()
	entry_container.name = "QuestEntry_" + quest_id

	# 任务名称
	var name_label = Label.new()
	name_label.text = quest_name
	name_label.add_theme_font_size_override("font_size", 14)

	if is_completed:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.3, 1.0))  # 绿色（已完成）
	else:
		name_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))  # 深灰色（进行中）

	entry_container.add_child(name_label)

	# 进度条
	var progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = total
	progress_bar.value = progress
	progress_bar.custom_minimum_size = Vector2(100, 16)

	entry_container.add_child(progress_bar)

	# 进度文本
	var progress_text = Label.new()
	progress_text.text = str(progress) + "/" + str(total)
	progress_text.add_theme_font_size_override("font_size", 12)

	entry_container.add_child(progress_text)

	# 添加到容器
	quest_list_container.add_child(entry_container)

	# 注册到字典
	quest_entries[quest_id] = {
		"name": quest_name,
		"progress": progress,
		"total": total,
		"is_completed": is_completed,
		"progress_bar": progress_bar
	}

## ============================================================
## 实时更新单个任务进度
## ============================================================

func _on_quest_updated(quest_id: String, progress: int, total: int) -> void:
	if not quest_entries.has(quest_id):
		return

	var entry = quest_entries[quest_id]
	entry["progress"] = progress

	# 更新进度条动画
	var progress_bar: ProgressBar = entry.get("progress_bar")
	if progress_bar:
		_animate_progress_update(progress_bar, progress)

## ============================================================
## 进度条增长动画
## ============================================================

func _animate_progress_update(progress_bar: ProgressBar, new_value: int) -> void:
	var tween = progress_bar.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(progress_bar, "value", new_value, 0.3)

## ============================================================
## 任务完成回调
## ============================================================

func _on_quest_completed_signal(quest_id: String) -> void:
	if not quest_entries.has(quest_id):
		return

	var entry = quest_entries[quest_id]
	entry["is_completed"] = true

	# 更新颜色为绿色（已完成）
	var entry_container: HBoxContainer = quest_list_container.get_node_or_null("QuestEntry_" + quest_id)
	if entry_container:
		var name_label: Label = entry_container.get_child(0)
		if name_label:
			name_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.3, 1.0))

	# 发出完成信号
	quest_completed.emit(quest_id)

## ============================================================
## 隐藏任务追踪器
## ============================================================

func hide_tracker() -> void:
	visible = false