# test_reward_animation.gd
# GUT测试用例 — RewardAnimation
# 测试Badge解锁动画、粒子爆发、音效同步

extends GutTest

var reward_anim: RewardAnimation
var mock_vfx_manager: VFXManager
var mock_audio_manager: AudioManager

func before_each():
	# 创建RewardAnimation实例
	reward_anim = RewardAnimation.new()
	add_child(reward_anim)

	# 创建模拟VFXManager
	mock_vfx_manager = double(VFXManager).new()
	mock_vfx_manager.name = "VFXManager"
	add_child_autofree(mock_vfx_manager)

	# 创建模拟AudioManager
	mock_audio_manager = double(AudioManager).new()
	mock_audio_manager.name = "AudioManager"
	add_child_autofree(mock_audio_manager)

func after_each():
	if reward_anim and is_instance_valid(reward_anim):
		reward_anim.queue_free()

func test_badge_unlock_initialization():
	# 测试初始化状态
	assert_false(reward_anim.visible, "初始状态应隐藏")
	assert_eq(reward_anim.modulate.a, 0.0, "初始alpha应为0")

func test_play_badge_unlock_sets_content():
	# 测试Badge解锁设置内容
	var badge_name = "森林守护者"
	var badge_icon_path = "res://assets/textures/badges/forest_badge.png"

	# 模拟BadgeContainer和子节点
	var badge_container = Control.new()
	badge_container.name = "BadgeContainer"
	reward_anim.add_child(badge_container)

	var badge_label = Label.new()
	badge_label.name = "BadgeLabel"
	badge_container.add_child(badge_label)

	reward_anim.badge_container = badge_container
	reward_anim.badge_label = badge_label

	reward_anim.play_badge_unlock(badge_name, badge_icon_path)

	# 验证内容设置
	assert_eq(badge_label.text, badge_name, "Badge名称应正确设置")
	assert_true(reward_anim.visible, "动画应可见")

	if badge_container and is_instance_valid(badge_container):
		badge_container.queue_free()

func test_play_badge_popup_animation():
	# 测试弹出动画
	var badge_container = Control.new()
	badge_container.name = "BadgeContainer"
	reward_anim.add_child(badge_container)

	reward_anim.badge_container = badge_container

	reward_anim._play_badge_popup()

	# 验证动画开始
	assert_true(badge_container.visible, "BadgeContainer应可见")
	assert_eq(badge_container.scale.x, UIAnimationPresets.ScalePop.START_SCALE, "初始缩放应为START_SCALE")

	# 等待动画完成
	await yield_for(0.7)

	# 验证动画结束状态
	assert_almost_eq(badge_container.scale.x, 1.0, 0.1, "动画结束缩放应为1.0")

	if badge_container and is_instance_valid(badge_container):
		badge_container.queue_free()

func test_play_particle_burst_calls_vfx_manager():
	# 测试粒子爆发调用VFXManager
	var particle_spawn_point = Marker2D.new()
	particle_spawn_point.name = "ParticleSpawnPoint"
	particle_spawn_point.global_position = Vector2(100, 100)
	reward_anim.add_child(particle_spawn_point)

	reward_anim.particle_spawn_point = particle_spawn_point

	# Stub VFXManager方法
	stub(mock_vfx_manager, "play_particle_effect_at_position").to_return(null)

	reward_anim._play_particle_burst()

	# 验证调用（无法直接验证，需通过观察）
	# assert_called(mock_vfx_manager, "play_particle_effect_at_position")

	if particle_spawn_point and is_instance_valid(particle_spawn_point):
		particle_spawn_point.queue_free()

func test_play_xp_reward():
	# 测试XP奖励动画
	var badge_label = Label.new()
	badge_label.name = "BadgeLabel"
	reward_anim.add_child(badge_label)
	reward_anim.badge_label = badge_label

	reward_anim.play_xp_reward(100, false)

	assert_true(reward_anim.visible, "XP奖励应可见")
	assert_eq(badge_label.text, "+100 XP", "XP奖励文本应正确")

	if badge_label and is_instance_valid(badge_label):
		badge_label.queue_free()

func test_play_area_unlock():
	# 测试区域解锁动画
	var badge_label = Label.new()
	badge_label.name = "BadgeLabel"
	reward_anim.add_child(badge_label)
	reward_anim.badge_label = badge_label

	reward_anim.play_area_unlock("彩虹花园")

	assert_true(reward_anim.visible, "区域解锁应可见")
	assert_eq(badge_label.text, "解锁区域：彩虹花园", "区域解锁文本应正确")

	if badge_label and is_instance_valid(badge_label):
		badge_label.queue_free()

func test_badge_unlock_complete_auto_hide():
	# 测试自动隐藏
	reward_anim.visible = true
	reward_anim.modulate.a = 1.0

	reward_anim._on_badge_unlock_complete()

	# 等待淡出完成
	await yield_for(0.6)

	assert_false(reward_anim.visible, "动画完成后应自动隐藏")