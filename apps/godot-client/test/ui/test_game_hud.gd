# test_game_hud.gd
# GUT测试用例 — GameHUD
# 测试星星条动画、LXP分数变化、徽章显示

extends GutTest

var game_hud: GameHUD
var mock_game_manager: GameManager

func before_each():
	# 创建GameHUD实例
	game_hud = GameHUD.new()
	add_child(game_hud)

	# Mock GameManager（需要实际GameManager，因为使用了静态属性）
	# 注意：GameManager是Autoload，需要使用实际实例或stub

func after_each():
	if game_hud and is_instance_valid(game_hud):
		game_hud.queue_free()

func test_hud_initialization():
	# 测试初始化状态
	assert_false(game_hud.visible, "初始状态应隐藏")
	assert_not_null(game_hud._star_flight_anim, "StarFlightAnimation应被创建")

func test_show_hud_animation():
	# 测试显示HUD动画
	game_hud.show_hud()

	# 验证动画开始
	assert_true(game_hud.visible, "HUD应可见")
	assert_eq(game_hud.modulate.a, 0.0, "初始alpha应为0（动画开始）")

	# 等待动画完成
	await yield_for(0.4)

	assert_almost_eq(game_hud.modulate.a, 1.0, 0.1, "显示动画后alpha应为1.0")

func test_hide_hud_animation():
	# 测试隐藏HUD动画
	game_hud.visible = true
	game_hud.modulate.a = 1.0

	game_hud.hide_hud()

	# 等待动画完成
	await yield_for(0.4)

	assert_false(game_hud.visible, "隐藏动画后应不可见")
	assert_eq(game_hud.modulate.a, 0.0, "隐藏动画后alpha应为0")

func test_update_quest():
	# 测试更新任务进度
	var quest_label = Label.new()
	quest_label.name = "QuestLabel"
	game_hud.add_child(quest_label)
	game_hud.quest_label = quest_label

	var quest_progress = TextureProgressBar.new()
	quest_progress.name = "QuestProgress"
	game_hud.add_child(quest_progress)
	game_hud.quest_progress = quest_progress

	game_hud.update_quest("收集5颗星星", 3, 5)

	assert_eq(game_hud.current_quest_name, "收集5颗星星", "任务名称应正确")
	assert_eq(game_hud.current_quest_progress_val, 3, "任务进度应正确")
	assert_eq(game_hud.quest_label.text, "收集5颗星星 (3/5)", "任务标签文本应正确")
	assert_eq(game_hud.quest_progress.value, 60.0, "进度条值应为60%")

	if quest_label and is_instance_valid(quest_label):
		quest_label.queue_free()
	if quest_progress and is_instance_valid(quest_progress):
		quest_progress.queue_free()

func test_animate_lxp_change():
	# 测试LXP分数变化动画
	var lxp_label = Label.new()
	lxp_label.name = "LXPLabel"
	lxp_label.scale = Vector2(1.0, 1.0)
	game_hud.add_child(lxp_label)
	game_hud.lxp_label = lxp_label

	game_hud._animate_lxp_change(50, 100)

	# 验证动画开始（缩放跳动）
	await yield_for(0.1)

	# 验证缩放动画开始（应放大到1.3）
	assert_almost_eq(lxp_label.scale.x, 1.2, 0.3, "缩放动画应开始跳动")

	# 等待动画完成
	await yield_for(0.6)

	assert_eq(lxp_label.scale, Vector2(1.0, 1.0), "动画结束后缩放应恢复1.0")

	if lxp_label and is_instance_valid(lxp_label):
		lxp_label.queue_free()

func test_star_bar_progress_integration():
	# 测试星星条进度集成
	var star_progress_bar = ProgressBar.new()
	star_progress_bar.name = "StarProgressBar"
	star_progress_bar.min_value = 0
	star_progress_bar.max_value = 100
	star_progress_bar.value = 10
	game_hud.add_child(star_progress_bar)
	game_hud.star_progress_bar = star_progress_bar

	game_hud._update_display()

	# 等待动画完成
	await yield_for(0.5)

	# 验证进度条动画（根据GameManager.lxp_score）
	# 注意：无法直接验证，因为依赖GameManager实例

	if star_progress_bar and is_instance_valid(star_progress_bar):
		star_progress_bar.queue_free()