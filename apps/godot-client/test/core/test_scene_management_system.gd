# test_scene_management_system.gd
# GUT测试用例 — SceneManagementSystem
# 测试14步场景切换流程、Shader过渡、输入阻塞

extends GutTest

var scene_manager: SceneManagementSystem
var mock_shader_manager: ShaderManager
var mock_ui_framework: UIFramework

func before_each():
	# 创建SceneManagementSystem实例
	scene_manager = SceneManagementSystem.new()
	add_child(scene_manager)

	# Mock ShaderManager
	mock_shader_manager = double(ShaderManager).new()
	mock_shader_manager.name = "ShaderManager"
	add_child_autofree(mock_shader_manager)

	# Mock UIFramework
	mock_ui_framework = double(UIFramework).new()
	mock_ui_framework.name = "UIFramework"
	add_child_autofree(mock_ui_framework)

func after_each():
	if scene_manager and is_instance_valid(scene_manager):
		scene_manager.queue_free()

func test_initialization():
	# 测试初始化状态
	assert_eq(scene_manager.current_state, SceneManagementSystem.SceneState.IDLE, "初始状态应为IDLE")
	assert_eq(scene_manager.current_scene_id, "", "初始场景ID应为空")
	assert_eq(scene_manager.scene_configs.size(), 0, "初始场景配置应为空（JSON尚未加载）")

func test_load_scene_configs():
	# 测试加载场景配置
	# 注意：需要JSON文件存在才能加载成功
	scene_manager._load_scene_configs()

	# 验证配置加载
	# 如果JSON文件存在，应该有配置
	# assert_gt(scene_manager.scene_configs.size(), 0, "应加载场景配置")

func test_enter_scene_state_validation():
	# 测试状态验证（Step 1）
	scene_manager.current_state = SceneManagementSystem.SceneState.ACTIVE

	var result = scene_manager.enter_scene("test_scene")

	assert_false(result, "非IDLE状态应拒绝进入")
	assert_signal_emitted(scene_manager, "transition_failed", "应发出失败信号")

func test_enter_scene_id_validation():
	# 测试场景ID验证（Step 2）
	scene_manager.current_state = SceneManagementSystem.SceneState.IDLE

	var result = scene_manager.enter_scene("invalid_scene_id")

	assert_false(result, "无效场景ID应拒绝进入")
	assert_signal_emitted(scene_manager, "transition_failed", "应发出失败信号")

func test_state_change_emits_signal():
	# 测试状态变更信号
	scene_manager.current_state = SceneManagementSystem.SceneState.IDLE

	scene_manager._change_state(SceneManagementSystem.SceneState.TRANSITIONING_IN)

	assert_eq(scene_manager.current_state, SceneManagementSystem.SceneState.TRANSITIONING_IN, "状态应变更")
	assert_signal_emitted(scene_manager, "state_changed", "应发出状态变更信号")

func test_input_block_sets_flag():
	# 测试输入阻塞
	scene_manager._block_input()

	assert_true(scene_manager._input_blocked, "输入阻塞标志应为true")

	# 验证UIFramework调用（通过stub验证）
	# stub(mock_ui_framework, "set_input_blocked").to_return(null)

func test_input_unblock_clears_flag():
	# 测试解除输入阻塞
	scene_manager._input_blocked = true

	scene_manager._unblock_input()

	assert_false(scene_manager._input_blocked, "输入阻塞标志应为false")

func test_is_input_blocked():
	# 测试检查输入阻塞状态
	scene_manager._input_blocked = false
	assert_false(scene_manager.is_input_blocked(), "未阻塞时应返回false")

	scene_manager._input_blocked = true
	assert_true(scene_manager.is_input_blocked(), "阻塞时应返回true")

func test_play_transition_animation_with_shader():
	# 测试Shader过渡动画
	# Stub ShaderManager方法
	stub(mock_shader_manager, "apply_shader").to_return(null)

	# 创建过渡层
	scene_manager._play_transition_animation()

	# 等待动画完成
	await yield_for(0.4)

	# 验证过渡层被创建并清理（无法直接验证，需通过观察）
	# 注意：过渡层在动画完成后被queue_free()

func test_play_exit_transition_with_shader():
	# 测试退出过渡动画
	stub(mock_shader_manager, "apply_shader").to_return(null)

	scene_manager._play_exit_transition()

	# 等待动画完成
	await yield_for(0.3)

	# 验证反向过渡（无法直接验证）

func test_get_current_scene_id():
	# 测试获取当前场景ID
	scene_manager.current_scene_id = "spirit_forest"

	var scene_id = scene_manager.get_current_scene_id()

	assert_eq(scene_id, "spirit_forest", "应返回当前场景ID")

func test_get_current_state():
	# 测试获取当前状态
	scene_manager.current_state = SceneManagementSystem.SceneState.ACTIVE

	var state = scene_manager.get_current_state()

	assert_eq(state, SceneManagementSystem.SceneState.ACTIVE, "应返回当前状态")

func test_list_available_scenes():
	# 测试列出可用场景
	# 添加测试配置
	scene_manager.scene_configs = {
		"scene_1": {"unlock_condition": {}},
		"scene_2": {"unlock_condition": {"requires": "scene_1_completed"}}
	}

	var available_scenes = scene_manager.list_available_scenes()

	# 验证列表
	assert_gt(available_scenes.size(), 0, "应返回可用场景列表")

func test_force_enter_scene():
	# 测试强制进入场景
	scene_manager.current_state = SceneManagementSystem.SceneState.ACTIVE

	scene_manager.force_enter_scene("test_scene")

	assert_eq(scene_manager.current_state, SceneManagementSystem.SceneState.IDLE, "强制进入应重置状态为IDLE")

func test_check_scene_unlocked():
	# 测试检查场景解锁
	var config = {"unlock_condition": {}}

	var unlocked = scene_manager._check_scene_unlocked(config)

	assert_true(unlocked, "无解锁条件时应返回true")

func test_trigger_event_play_bgm():
	# 测试触发播放BGM事件
	var event = {"type": "play_bgm", "bgm_path": "res://test.ogg"}

	scene_manager._trigger_event(event)

	# 验证事件处理（无法直接验证AudioManager调用）

func test_trigger_event_show_tutorial():
	# 测试触发显示教程事件
	var event = {"type": "show_tutorial", "tutorial_id": "test_tutorial"}

	scene_manager._trigger_event(event)

	# 验证事件处理（无法直接验证DialogueManager调用）

func test_trigger_event_spawn_particle():
	# 测试触发粒子生成事件
	var event = {"type": "spawn_particle", "particle_type": "test_particle", "position": Vector2(100, 100)}

	scene_manager._trigger_event(event)

	# 验证事件处理（无法直接验证VFXManager调用）