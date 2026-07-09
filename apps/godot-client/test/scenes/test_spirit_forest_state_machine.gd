# test_spirit_forest_state_machine.gd
# GUT 测试用例 — SpiritForestConfig 状态机 + 配置
# 测试 7 步状态枚举、对话文本读取、星星奖励配置、评估类型映射

extends GutTest

const SpiritForestConfig = preload("res://assets/scripts/components/scene_config/spirit_forest_config.gd")

# ── Step 枚举完整性 ──

func test_step_enum_has_7_values():
	# 通过直接引用所有枚举值来验证
	var steps := [
		SpiritForestConfig.Step.SPARK_INTRO_NAME,
		SpiritForestConfig.Step.DISCOVER_BIG_TREE,
		SpiritForestConfig.Step.OAKLEY_WAKE,
		SpiritForestConfig.Step.WATERING_CAN_PICKUP,
		SpiritForestConfig.Step.WATERING_TUTORIAL,
		SpiritForestConfig.Step.WATERING_PRACTICE,
		SpiritForestConfig.Step.MISSION_COMPLETE_EXIT,
	]
	assert_eq(steps.size(), 7, "Step 枚举应有 7 个值")

func test_step_enum_sequential_values():
	assert_eq(SpiritForestConfig.Step.SPARK_INTRO_NAME, 0)
	assert_eq(SpiritForestConfig.Step.DISCOVER_BIG_TREE, 1)
	assert_eq(SpiritForestConfig.Step.OAKLEY_WAKE, 2)
	assert_eq(SpiritForestConfig.Step.WATERING_CAN_PICKUP, 3)
	assert_eq(SpiritForestConfig.Step.WATERING_TUTORIAL, 4)
	assert_eq(SpiritForestConfig.Step.WATERING_PRACTICE, 5)
	assert_eq(SpiritForestConfig.Step.MISSION_COMPLETE_EXIT, 6)

# ── OakleySubStep 枚举 ──

func test_oakley_substep_enum():
	assert_eq(SpiritForestConfig.OakleySubStep.WAKING, 0)
	assert_eq(SpiritForestConfig.OakleySubStep.GREETING, 1)
	assert_eq(SpiritForestConfig.OakleySubStep.INTRO, 2)
	assert_eq(SpiritForestConfig.OakleySubStep.REQUEST, 3)

# ── 星星经济常量 ──

func test_star_values():
	assert_eq(SpiritForestConfig.STAR_NAME_COLLECTION, 2)
	assert_eq(SpiritForestConfig.STAR_GREET_OAKLEY, 1)
	assert_eq(SpiritForestConfig.STAR_TUTORIAL_SUCCESS, 3)
	assert_eq(SpiritForestConfig.STAR_PRACTICE_SUCCESS, 5)
	assert_eq(SpiritForestConfig.TOTAL_STARS, 11)

func test_total_stars_equals_sum():
	var total := SpiritForestConfig.STAR_NAME_COLLECTION \
		+ SpiritForestConfig.STAR_GREET_OAKLEY \
		+ SpiritForestConfig.STAR_TUTORIAL_SUCCESS \
		+ SpiritForestConfig.STAR_PRACTICE_SUCCESS
	assert_eq(SpiritForestConfig.TOTAL_STARS, total, "TOTAL_STARS 应等于各步星星之和")

# ── 重试与超时常量 ──

func test_retry_constants():
	assert_eq(SpiritForestConfig.MAX_TUTORIAL_ATTEMPTS, 3)
	assert_eq(SpiritForestConfig.MAX_PRACTICE_ATTEMPTS, 3)

func test_timeout_constants_positive():
	assert_gt(SpiritForestConfig.SILENCE_TIMEOUT, 0.0)
	assert_gt(SpiritForestConfig.MAX_RECORD_DURATION, 0.0)

# ── 动画时长常量 ──

func test_animation_constants_positive():
	assert_gt(SpiritForestConfig.SPARK_FLY_IN_DURATION, 0.0)
	assert_gt(SpiritForestConfig.CAMERA_PAN_DURATION, 0.0)
	assert_gt(SpiritForestConfig.OAKLEY_WAKE_DURATION, 0.0)
	assert_gt(SpiritForestConfig.FLOWER_GROWTH_DURATION, 0.0)
	assert_gt(SpiritForestConfig.SCENE_FADE_DURATION, 0.0)

func test_camera_positions_ordered():
	assert_lt(SpiritForestConfig.CAMERA_BIG_TREE_X, SpiritForestConfig.CAMERA_DEFAULT_X,
		"大树相机位置（负X）应在默认位置左边")

# ── 对话文本读取（静态方法） ──

func test_get_dialogue_en():
	var text: String = SpiritForestConfig.get_dialogue("spark_greeting", "en")
	assert_eq(text, "Hi! I'm Spark!")

func test_get_dialogue_zh():
	var text: String = SpiritForestConfig.get_dialogue("spark_greeting", "zh")
	assert_eq(text, "嗨！我是 Spark！")

func test_get_dialogue_unknown_lang_fallback():
	var text: String = SpiritForestConfig.get_dialogue("spark_greeting", "fr")
	assert_eq(text, "Hi! I'm Spark!", "未知语言应 fallback 到英文")

func test_get_dialogue_unknown_key():
	var text: String = SpiritForestConfig.get_dialogue("nonexistent_key", "en")
	assert_eq(text, "", "未知 key 返回空字符串")

func test_all_required_dialogue_keys_present():
	var required_keys := [
		"spark_greeting", "spark_ask_name", "spark_name_celebrate",
		"spark_look_tree", "spark_go_hint",
		"oakley_greeting", "oakley_intro", "oakley_request",
		"oakley_give_can", "tap_watering_can", "spark_got_can",
		"spark_demo_sentence", "spark_try_with_me", "spark_well_done",
		"spark_almost", "spark_keyword_hint",
		"spark_practice", "spark_practice_success",
		"spark_tell_oakley", "oakley_wonderful", "oakley_follow_me", "spark_follow",
	]
	for key in required_keys:
		var text_en: String = SpiritForestConfig.get_dialogue(key, "en")
		var text_zh: String = SpiritForestConfig.get_dialogue(key, "zh")
		assert_false(text_en.is_empty(), "Key '%s' 英文文本不应为空" % key)
		assert_false(text_zh.is_empty(), "Key '%s' 中文文本不应为空" % key)

func test_name_celebrate_has_placeholder():
	var text: String = SpiritForestConfig.get_dialogue("spark_name_celebrate", "en")
	assert_true(text.contains("%s"), "名字庆祝文本应包含 %s 占位符")
	var formatted: String = text % "Alice"
	assert_eq(formatted, "Nice to meet you, Alice!")

# ── 评估类型映射 ──

func test_assessment_type_for_assessed_steps():
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.SPARK_INTRO_NAME), "name_collection")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.OAKLEY_WAKE), "greet_oakley")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.WATERING_TUTORIAL), "watering_tutorial")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.WATERING_PRACTICE), "watering_practice")

func test_assessment_type_empty_for_non_assessed_steps():
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.DISCOVER_BIG_TREE), "")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.WATERING_CAN_PICKUP), "")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.MISSION_COMPLETE_EXIT), "")

# ── 目标场景路径 ──

func test_target_scene_path():
	assert_true(SpiritForestConfig.TARGET_SCENE_PATH.ends_with("RainbowGarden.tscn"),
		"目标场景应为 RainbowGarden")
