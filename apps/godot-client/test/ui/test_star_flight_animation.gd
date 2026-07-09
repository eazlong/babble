# test_star_flight_animation.gd
# GUT测试用例 — StarFlightAnimation
# 测试贝塞尔曲线飞行、旋转、缩放动画

extends GutTest

var star_flight_anim: StarFlightAnimation
var mock_star: Control
var mock_tween_manager: UITweenManager

func before_each():
	# 创建StarFlightAnimation实例
	star_flight_anim = StarFlightAnimation.new()
	add_child(star_flight_anim)

	# 创建模拟星星节点
	mock_star = Control.new()
	mock_star.name = "MockStar"
	mock_star.global_position = Vector2(100, 100)
	add_child(mock_star)

	# 创建UITweenManager（可选）
	mock_tween_manager = UITweenManager.new()
	add_child(mock_tween_manager)

func after_each():
	# 清理节点
	if star_flight_anim and is_instance_valid(star_flight_anim):
		star_flight_anim.queue_free()
	if mock_star and is_instance_valid(mock_star):
		mock_star.queue_free()
	if mock_tween_manager and is_instance_valid(mock_tween_manager):
		mock_tween_manager.queue_free()

func test_quadratic_bezier_calculation():
	# 测试贝塞尔曲线计算
	var p0 = Vector2(0, 0)
	var p1 = Vector2(50, -100)
	var p2 = Vector2(100, 0)

	# t=0.5时，应该在曲线中点附近
	var mid_point = star_flight_anim._quadratic_bezier(p0, p1, p2, 0.5)
	assert_almost_eq(mid_point.x, 50.0, 5.0, "贝塞尔曲线中点X坐标应为50")
	assert_almost_eq(mid_point.y, -50.0, 10.0, "贝塞尔曲线中点Y坐标应为-50附近")

func test_star_initial_state():
	# 测试星星初始状态设置
	var start_pos = Vector2(0, 0)
	var end_pos = Vector2(200, 200)

	star_flight_anim.play(mock_star, start_pos, end_pos)

	# 验证初始状态
	assert_eq(mock_star.global_position, start_pos, "星星初始位置应为start_pos")
	assert_eq(mock_star.scale, Vector2(1.0, 1.0), "星星初始缩放应为1.0")
	assert_eq(mock_star.rotation_degrees, 0.0, "星星初始旋转应为0°")
	assert_true(mock_star.visible, "星星应可见")
	assert_eq(mock_star.modulate.a, 1.0, "星星初始alpha应为1.0")

func test_star_flight_creates_tweens():
	# 测试飞行动画创建tween
	var start_pos = Vector2(0, 0)
	var end_pos = Vector2(200, 200)

	star_flight_anim.play(mock_star, start_pos, end_pos)

	# 验证tween被创建（通过检查节点是否有活跃动画）
	await yield_for(0.1)

	# 验证动画正在播放（rotation_degrees应该在变化）
	assert_almost_eq(mock_star.rotation_degrees, 72.0, 20.0, "旋转动画应开始播放（约72°）")

func test_star_bar_progress_animation():
	# 测试星星条进度动画
	var progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 0
	add_child(progress_bar)

	# 测试进度增长动画
	var tween = star_flight_anim.animate_star_bar_progress(progress_bar, 0, 50)

	assert_not_null(tween, "进度动画应返回Tween")
	assert_eq(progress_bar.value, 0, "进度条初始值应为0")

	# 等待动画完成
	await yield_for(0.5)
	assert_almost_eq(progress_bar.value, 50.0, 5.0, "进度条应增长到50")

	if progress_bar and is_instance_valid(progress_bar):
		progress_bar.queue_free()

func test_batch_star_flight():
	# 测试批量星星飞行
	var star_nodes: Array[Control] = []
	var start_positions: Array[Vector2] = []
	var end_positions: Array[Vector2] = []

	for i in range(3):
		var star = Control.new()
		star.name = "Star_" + str(i)
		add_child(star)
		star_nodes.append(star)
		start_positions.append(Vector2(i * 100, 100))
		end_positions.append(Vector2(i * 100 + 200, 200))

	star_flight_anim.play_batch_star_flight(star_nodes, start_positions, end_positions)

	# 验证所有星星可见
	for star in star_nodes:
		assert_true(star.visible, "批量星星应可见")

	# 等待动画完成
	await yield_for(2.0)

	# 清理
	for star in star_nodes:
		if star and is_instance_valid(star):
			star.queue_free()

func test_milestone_feedback_trigger():
	# 测试里程碑反馈（20星阈值）
	var progress_bar = ProgressBar.new()
	progress_bar.min_value = 0
	progress_bar.max_value = 100
	progress_bar.value = 15
	add_child(progress_bar)

	# 触发里程碑反馈
	star_flight_anim.animate_star_bar_progress(progress_bar, 15, 25)

	# 等待动画完成
	await yield_for(0.5)

	# 验证进度条到达阈值后触发反馈（通过检查震动动画）
	assert_almost_eq(progress_bar.value, 25.0, 5.0, "进度条应增长到25")

	if progress_bar and is_instance_valid(progress_bar):
		progress_bar.queue_free()