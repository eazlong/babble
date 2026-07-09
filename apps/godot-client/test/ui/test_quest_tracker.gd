# test_quest_tracker.gd
# GUT测试用例 — QuestTracker
# 测试任务进度更新、多任务列表、完成状态

extends GutTest

var quest_tracker: QuestTracker

func before_each():
	quest_tracker = QuestTracker.new()
	add_child(quest_tracker)

func after_each():
	if quest_tracker and is_instance_valid(quest_tracker):
		quest_tracker.queue_free()

func test_initialization():
	# 测试初始化状态
	assert_false(quest_tracker.visible, "初始状态应隐藏")
	assert_eq(quest_tracker.quest_entries.size(), 0, "初始任务字典应为空")

func test_update_quest_list():
	# 测试更新任务列表
	var quest_list_container = VBoxContainer.new()
	quest_list_container.name = "QuestListContainer"
	quest_tracker.add_child(quest_list_container)
	quest_tracker.quest_list_container = quest_list_container

	var quests = [
		{"quest_id": "quest_1", "name": "收集星星", "progress": 3, "total": 5, "is_completed": false},
		{"quest_id": "quest_2", "name": "完成对话", "progress": 1, "total": 3, "is_completed": false},
		{"quest_id": "quest_3", "name": "解锁区域", "progress": 1, "total": 1, "is_completed": true}
	]

	quest_tracker.update_quest_list(quests)

	# 验证显示状态
	assert_true(quest_tracker.visible, "任务列表应可见")
	assert_eq(quest_list_container.get_child_count(), 3, "应显示3个任务条目")
	assert_eq(quest_tracker.quest_entries.size(), 3, "任务字典应有3个条目")

	if quest_list_container and is_instance_valid(quest_list_container):
		quest_list_container.queue_free()

func test_create_quest_entry():
	# 测试创建任务条目
	var quest_list_container = VBoxContainer.new()
	quest_tracker.add_child(quest_list_container)
	quest_tracker.quest_list_container = quest_list_container

	var quest_data = {
		"quest_id": "test_quest",
		"name": "测试任务",
		"progress": 2,
		"total": 5,
		"is_completed": false
	}

	quest_tracker._create_quest_entry(quest_data)

	# 验证条目创建
	assert_eq(quest_list_container.get_child_count(), 1, "应创建1个任务条目")
	assert_true(quest_tracker.quest_entries.has("test_quest"), "任务字典应包含test_quest")

	# 验证进度数据
	var entry = quest_tracker.quest_entries["test_quest"]
	assert_eq(entry["progress"], 2, "进度应为2")
	assert_eq(entry["total"], 5, "总数应为5")

	if quest_list_container and is_instance_valid(quest_list_container):
		quest_list_container.queue_free()

func test_quest_updated_animation():
	# 测试任务进度更新动画
	var quest_list_container = VBoxContainer.new()
	quest_tracker.add_child(quest_list_container)
	quest_tracker.quest_list_container = quest_list_container

	var quest_data = {
		"quest_id": "update_quest",
		"name": "更新测试",
		"progress": 2,
		"total": 5,
		"is_completed": false
	}

	quest_tracker._create_quest_entry(quest_data)

	var progress_bar: ProgressBar = quest_tracker.quest_entries["update_quest"]["progress_bar"]
	assert_eq(progress_bar.value, 2, "初始进度应为2")

	# 触发进度更新
	quest_tracker._on_quest_updated("update_quest", 4, 5)

	# 等待动画完成
	await yield_for(0.4)

	assert_almost_eq(progress_bar.value, 4.0, 0.5, "进度动画后应为4")

	if quest_list_container and is_instance_valid(quest_list_container):
		quest_list_container.queue_free()

func test_quest_completed_changes_color():
	# 测试任务完成改变颜色
	var quest_list_container = VBoxContainer.new()
	quest_tracker.add_child(quest_list_container)
	quest_tracker.quest_list_container = quest_list_container

	var quest_data = {
		"quest_id": "complete_quest",
		"name": "完成测试",
		"progress": 5,
		"total": 5,
		"is_completed": false
	}

	quest_tracker._create_quest_entry(quest_data)

	# 触发完成
	quest_tracker._on_quest_completed_signal("complete_quest")

	# 验证状态更新
	assert_true(quest_tracker.quest_entries["complete_quest"]["is_completed"], "任务应标记为完成")

	# 验证颜色变化（绿色）
	var entry_container: HBoxContainer = quest_list_container.get_node_or_null("QuestEntry_complete_quest")
	if entry_container:
		var name_label: Label = entry_container.get_child(0)
		var color = name_label.get_theme_color("font_color")
		assert_almost_eq(color.r, 0.5, 0.1, "完成颜色应为绿色（R≈0.5）")
		assert_almost_eq(color.g, 0.8, 0.1, "完成颜色应为绿色（G≈0.8）")

	if quest_list_container and is_instance_valid(quest_list_container):
		quest_list_container.queue_free()

func test_hide_tracker():
	# 测试隐藏追踪器
	quest_tracker.visible = true
	quest_tracker.hide_tracker()

	assert_false(quest_tracker.visible, "追踪器应隐藏")