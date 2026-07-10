# test_spirit_forest_state_machine.gd
# GUT 测试用例 — SpiritForestConfig 序章状态机 + 配置

extends GutTest

const SpiritForestConfig = preload("res://assets/scripts/components/scene_config/spirit_forest_config.gd")

func test_step_enum_has_3_prologue_values():
	var steps := [
		SpiritForestConfig.Step.FEIFEI_INTRO_NAME,
		SpiritForestConfig.Step.WORLD_REVEAL,
		SpiritForestConfig.Step.INN_BINDING_EXIT,
	]
	assert_eq(steps.size(), 3, "序章应有 3 个主步骤")

func test_step_enum_sequential_values():
	assert_eq(SpiritForestConfig.Step.FEIFEI_INTRO_NAME, 0)
	assert_eq(SpiritForestConfig.Step.WORLD_REVEAL, 1)
	assert_eq(SpiritForestConfig.Step.INN_BINDING_EXIT, 2)

func test_lxp_values():
	assert_eq(SpiritForestConfig.STAR_NAME_COLLECTION, 2)
	assert_eq(SpiritForestConfig.STAR_ACCEPT_QUEST, 2)
	assert_eq(SpiritForestConfig.TOTAL_STARS, 4)

func test_total_lxp_equals_sum():
	var total := SpiritForestConfig.STAR_NAME_COLLECTION + SpiritForestConfig.STAR_ACCEPT_QUEST
	assert_eq(SpiritForestConfig.TOTAL_STARS, total, "TOTAL_STARS 应等于序章奖励之和")

func test_retry_and_timeout_constants():
	assert_eq(SpiritForestConfig.MAX_ATTEMPTS, 3)
	assert_eq(SpiritForestConfig.SILENCE_TIMEOUT, 5.0)
	assert_gt(SpiritForestConfig.MAX_RECORD_DURATION, 0.0)

func test_animation_constants_positive():
	assert_gt(SpiritForestConfig.FEIFEI_FLY_IN_DURATION, 0.0)
	assert_gt(SpiritForestConfig.CAMERA_PAN_DURATION, 0.0)
	assert_gt(SpiritForestConfig.SCENE_FADE_DURATION, 0.0)

func test_get_dialogue_hello_prompt_en():
	var text: String = SpiritForestConfig.get_dialogue("feifei_greeting", "en")
	assert_eq(text, "Hello, thank goodness you're awake, outsider. I'm feifei. I found you in the Chaos Mist and brought you here. What's your %s name?")

func test_get_dialogue_silence_hint_zh():
	var text: String = SpiritForestConfig.get_dialogue("feifei_silence_hint", "zh")
	assert_eq(text, "试着用英语对 feifei(腓腓) 说 Hello 吧！")

func test_get_dialogue_unknown_lang_fallback():
	var text: String = SpiritForestConfig.get_dialogue("feifei_greeting", "fr")
	assert_eq(text, "Hello, thank goodness you're awake, outsider. I'm feifei. I found you in the Chaos Mist and brought you here. What's your %s name?", "未知语言应 fallback 到英文")

func test_get_dialogue_unknown_key():
	var text: String = SpiritForestConfig.get_dialogue("nonexistent_key", "en")
	assert_eq(text, "", "未知 key 返回空字符串")

func test_all_required_prologue_dialogue_keys_present():
	var required_keys := [
		"feifei_greeting",
		"feifei_silence_hint",
		"feifei_ask_name",
		"feifei_ask_special_name",
		"feifei_name_celebrate",
		"world_intro_mist_island",
		"world_intro_six_continents",
		"world_intro_mist",
		"world_intro_curse",
		"world_intro_quest",
		"feifei_quest_accept_hint",
		"feifei_quest_accepted",
		"inn_intro",
		"inn_intro_history",
		"inn_mechanic_intro",
		"inn_first_guest",
		"inn_follow_feifei",
		"inn_transition",
	]
	for key in required_keys:
		var text_en: String = SpiritForestConfig.get_dialogue(key, "en")
		var text_zh: String = SpiritForestConfig.get_dialogue(key, "zh")
		assert_false(text_en.is_empty(), "Key '%s' 英文文本不应为空" % key)
		assert_false(text_zh.is_empty(), "Key '%s' 中文文本不应为空" % key)

func test_name_celebrate_has_placeholder():
	var text: String = SpiritForestConfig.get_dialogue("feifei_name_celebrate", "en")
	assert_true(text.contains("%s"), "名字庆祝文本应包含 %s 占位符")
	var formatted: String = text % "Alice"
	assert_eq(formatted, "Alice sounds wonderful. You must be wondering where this is.")

func test_assessment_type_for_assessed_steps():
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.FEIFEI_INTRO_NAME), "name_collection")
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.WORLD_REVEAL), "quest_acceptance")

func test_assessment_type_empty_for_exit_step():
	assert_eq(SpiritForestConfig.get_assessment_type(SpiritForestConfig.Step.INN_BINDING_EXIT), "")

func test_target_scene_path():
	assert_true(SpiritForestConfig.TARGET_SCENE_PATH.ends_with("ChangAnMarket.tscn"),
		"序章完成后应进入长安西市")

func test_language_learning_config_defaults_to_chinese_learning_english():
	assert_eq(GameManager.SOURCE_LANGUAGE_CODE, "zh")
	assert_eq(GameManager.SOURCE_LANGUAGE_NAME, "中文")
	assert_eq(GameManager.SPECIAL_LANGUAGE_CODE, "en")
	assert_eq(GameManager.SPECIAL_LANGUAGE_NAME, "英语")
	assert_eq(GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME, "Carl")
