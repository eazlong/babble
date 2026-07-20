extends GutTest

const LessonResponseMatcherScript = preload("res://assets/scripts/core/lesson_response_matcher.gd")
const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")

func test_good_morning_accepts_core_keyword():
	var rule := {
		"clear_phrases": ["good morning"],
		"acceptable_phrases": ["morning"],
		"required_keywords": ["morning"],
		"optional_keywords": ["good"]
	}

	var result: Dictionary = LessonResponseMatcherScript.evaluate("morning", rule)

	assert_eq(result["tier"], LessonResponseMatcherScript.RESULT_UNDERSTANDABLE)
	assert_true(result["matched"].has("morning"))

func test_her_name_requires_her_and_name():
	var rule := {
		"clear_phrases": ["her name is a ling"],
		"required_keywords": ["her", "name"],
		"optional_keywords": ["meet", "classmate"],
		"confused_keywords": ["his"]
	}

	var result: Dictionary = LessonResponseMatcherScript.evaluate("Her name A-Ling", rule)

	assert_eq(result["tier"], LessonResponseMatcherScript.RESULT_UNDERSTANDABLE)
	assert_true(result["matched"].has("her"))
	assert_true(result["matched"].has("name"))

func test_her_name_rejects_his_confusion():
	var rule := {
		"required_keywords": ["her", "name"],
		"confused_keywords": ["his"]
	}

	var result: Dictionary = LessonResponseMatcherScript.evaluate("His name is A-Ling", rule)

	assert_eq(result["tier"], LessonResponseMatcherScript.RESULT_NEEDS_HELP)
	assert_eq(result["reason"], "confused_keyword")

func test_chang_an_market_dialogue_flow_loads():
	var loader: Variant = DialogueFlowLoaderScript.new()
	var ok: bool = loader.load_dialogue_flows()

	assert_true(ok, "长安西市第一课 dialogue flow 应能成功加载")
	assert_true(loader.has_flow("west_market_01.good_morning"))
	assert_true(loader.has_flow("west_market_01.afternoon_review_success"))

func test_chang_an_market_config_contains_target_words():
	var file := FileAccess.open("res://assets/resources/scene_configs/chang_an_market_lesson_01.json", FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	assert_true(parsed is Dictionary)
	var words: Array = parsed.get("target_words", [])
	assert_eq(words.size(), 9)
	assert_true(words.has("meet"))
	assert_true(words.has("afternoon"))

func test_chang_an_market_scene_instantiates():
	var packed: PackedScene = load("res://assets/scenes/ChangAnMarket.tscn")
	assert_not_null(packed)

	var scene: Node = packed.instantiate()
	assert_not_null(scene)
	assert_eq(scene.name, "ChangAnMarket")
	assert_not_null(scene.get_node_or_null("HUDLayer/QuestTracker/QuestLabel"))
	assert_not_null(scene.get_node_or_null("FeifeiLayer/FeifeiShoulder"))
	scene.free()
