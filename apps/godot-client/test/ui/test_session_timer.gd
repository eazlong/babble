# test_session_timer.gd
# GUT测试用例 — SessionTimer
# 测试会话计时、休息提醒、时长上限

extends GutTest

var session_timer: SessionTimer

func before_each():
	session_timer = SessionTimer.new()
	add_child(session_timer)

func after_each():
	if session_timer and is_instance_valid(session_timer):
		session_timer.queue_free()

func test_initialization():
	# 测试初始化状态
	assert_false(session_timer.visible, "初始状态应隐藏")
	assert_eq(session_timer._current_duration, 0.0, "初始时长应为0")
	assert_not_null(session_timer._session_timer, "SessionTimer应被创建")

func test_start_session():
	# 测试开始会话
	session_timer.start_session()

	# 验证计时启动
	assert_true(session_timer._session_timer.is_processing(), "SessionTimer应启动")
	assert_true(session_timer.visible, "计时器应可见")
	assert_gt(session_timer._session_start_time, 0, "开始时间应记录")

func test_end_session():
	# 测试结束会话
	session_timer.start_session()
	await yield_for(1.0)  # 等待1秒（模拟1分钟）

	session_timer.end_session()

	# 验证计时停止
	assert_false(session_timer._session_timer.is_processing(), "SessionTimer应停止")
	assert_false(session_timer.visible, "计时器应隐藏")
	assert_gt(session_timer._current_duration, 0, "应有时长记录")

func test_update_display():
	# 测试显示更新
	var timer_display = Label.new()
	timer_display.name = "TimerDisplay"
	session_timer.add_child(timer_display)
	session_timer.timer_display = timer_display

	var progress_circle = ProgressBar.new()
	progress_circle.name = "ProgressCircle"
	progress_circle.min_value = 0
	progress_circle.max_value = 100
	session_timer.add_child(progress_circle)
	session_timer.progress_circle = progress_circle

	session_timer._current_duration = 15.0
	session_timer._update_display()

	# 验证显示内容
	assert_eq(timer_display.text, "15分钟", "应显示15分钟")
	assert_eq(progress_circle.value, 50.0, "进度应为50%")

	if timer_display and is_instance_valid(timer_display):
		timer_display.queue_free()
	if progress_circle and is_instance_valid(progress_circle):
		progress_circle.queue_free()

func test_break_reminder_interval():
	# 测试休息提醒间隔（10分钟）
	session_timer._current_duration = 9.0
	session_timer._on_minute_tick()

	# 验证时长增长
	assert_eq(session_timer._current_duration, 10.0, "时长应增长到10分钟")

	# 触发休息提醒
	var reminder_popup = PanelContainer.new()
	reminder_popup.name = "ReminderPopup"
	reminder_popup.visible = false
	session_timer.add_child(reminder_popup)
	session_timer.reminder_popup = reminder_popup

	session_timer._trigger_break_reminder()

	# 验证提醒显示
	assert_true(reminder_popup.visible, "提醒弹窗应显示")

	# 等待自动隐藏
	await yield_for(4.0)

	assert_false(reminder_popup.visible, "提醒弹窗应自动隐藏")

	if reminder_popup and is_instance_valid(reminder_popup):
		reminder_popup.queue_free()

func test_session_limit_reached():
	# 测试时长上限（30分钟）
	session_timer._current_duration = 30.0
	session_timer._session_timer = Timer.new()
	session_timer.add_child(session_timer._session_timer)
	session_timer._session_timer.start()

	session_timer._trigger_session_limit()

	# 验证计时停止
	assert_false(session_timer._session_timer.is_processing(), "SessionTimer应停止")

	# 验证提醒显示
	var reminder_popup = PanelContainer.new()
	reminder_popup.name = "ReminderPopup"
	reminder_popup.visible = false
	session_timer.add_child(reminder_popup)
	session_timer.reminder_popup = reminder_popup

	session_timer._trigger_session_limit()
	assert_true(reminder_popup.visible, "上限提醒应显示")

	if reminder_popup and is_instance_valid(reminder_popup):
		reminder_popup.queue_free()
	if session_timer._session_timer and is_instance_valid(session_timer._session_timer):
		session_timer._session_timer.queue_free()

func test_get_current_duration():
	# 测试获取当前时长
	session_timer._current_duration = 25.0
	var duration = session_timer.get_current_duration()

	assert_eq(duration, 25.0, "应返回当前时长25分钟")

func test_reset_session():
	# 测试重置会话
	session_timer._current_duration = 20.0
	session_timer.visible = true

	session_timer.reset_session()

	assert_eq(session_timer._current_duration, 0.0, "时长应重置为0")
	assert_false(session_timer.visible, "计时器应隐藏")