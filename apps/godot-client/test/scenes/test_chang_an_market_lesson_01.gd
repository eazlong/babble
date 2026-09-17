extends GutTest

const ControllerScript = preload("res://assets/scripts/scenes/ChangAnMarketController.gd")
const LessonResponseMatcherScript = preload("res://assets/scripts/core/lesson_response_matcher.gd")
const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")

const SCENE_PATH: String = "res://assets/scenes/ChangAnMarket.tscn"
const CONFIG_PATH: String = "res://assets/resources/scene_configs/chang_an_market_lesson_01.json"

# 情节 1 每一步"孩子真的会这么说"的样本
const NATURAL_UTTERANCES: Dictionary = {
	"name_register": "My name is Kaka",
	"ask_where_live": "I live in Beijing",
	"restore_city": "City",
	"restore_street": "Street",
	"restore_building": "Building",
	"restore_house": "House",
	"where_is_your_home": "My home is in Beijing"
}

# 容易串味的词：说了另一个词就不该过关
const CROSS_WORDS: Dictionary = {
	"restore_city": "street",
	"restore_street": "city",
	"restore_building": "house",
	"restore_house": "building"
}

func _load_config() -> Dictionary:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

func _step_by_id(config: Dictionary, step_id: String) -> Dictionary:
	for step in config.get("steps", []):
		if str(step.get("id", "")) == step_id:
			return step
	return {}

func _is_accepted(tier: String) -> bool:
	return tier == LessonResponseMatcherScript.RESULT_CLEAR or tier == LessonResponseMatcherScript.RESULT_UNDERSTANDABLE

# ── 场景结构 ──────────────────────────────────────────────

func test_scene_instantiates_with_expected_nodes() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	assert_not_null(packed, "ChangAnMarket.tscn 应能加载")
	var scene: Node = packed.instantiate()
	assert_eq(scene.name, "ChangAnMarket")
	assert_not_null(scene.get_node_or_null("HUDLayer/QuestTracker/QuestLabel"), "任务追踪标签应在")
	assert_not_null(scene.get_node_or_null("FeifeiLayer"), "腓腓肩位应在")
	scene.free()

# ── 配置装载 ──────────────────────────────────────────────

func test_controller_loads_nine_steps() -> void:
	var controller = ControllerScript.new()
	controller._load_config()
	assert_eq(controller.steps.size(), 9, "情节 1 应有 9 个步骤")
	assert_eq(str(controller.config.get("scene_name", "")), "雾门问居：初入长安")
	assert_eq(str(controller.config.get("unit", "")), "Unit 1 — Where do people live?")
	controller.free()

func test_target_words_cover_unit_one() -> void:
	var config := _load_config()
	var words: Array = config.get("target_words", [])
	assert_eq(words.size(), 9)
	for expected in ["city", "country", "street", "building", "house", "flat", "farm", "live", "home"]:
		assert_true(words.has(expected), "target_words 应包含 %s" % expected)

# ── 对话流引用 ────────────────────────────────────────────

func test_every_step_flow_resolves() -> void:
	var config := _load_config()
	var loader: Variant = DialogueFlowLoaderScript.new()
	assert_true(loader.load_dialogue_flows(), "对话流应能加载")

	var missing: Array[String] = []
	for step in config.get("steps", []):
		for key in ["flow_id", "success_flow_id", "retry_flow_id"]:
			var flow_id: String = str(step.get(key, ""))
			if flow_id.is_empty():
				continue
			if not loader.has_flow(flow_id):
				missing.append(flow_id)
	assert_eq(missing.size(), 0, "所有引用的 flow 都应存在，缺失：%s" % str(missing))

# ── 步骤文案（防止落回默认值）────────────────────────────

func test_every_step_has_title_and_status() -> void:
	var config := _load_config()
	var controller = ControllerScript.new()
	controller._load_config()
	for step in config.get("steps", []):
		var step_id: String = str(step.get("id", ""))
		assert_ne(controller._step_title(step_id), "长安西市", "步骤 %s 应有专属标题" % step_id)
		assert_ne(controller._step_status(step_id), "", "步骤 %s 应有专属状态文案" % step_id)
	controller.free()

# ── 语音判定：真实说法应过关 ──────────────────────────────

func test_natural_utterances_are_accepted() -> void:
	var config := _load_config()
	for step_id in NATURAL_UTTERANCES.keys():
		var step := _step_by_id(config, step_id)
		assert_false(step.is_empty(), "配置里应有步骤 %s" % step_id)
		var result: Dictionary = LessonResponseMatcherScript.evaluate(str(NATURAL_UTTERANCES[step_id]), step.get("asr", {}))
		assert_true(
			_is_accepted(str(result.get("tier", ""))),
			"「%s」应能通过步骤 %s，实际 tier=%s reason=%s" % [str(NATURAL_UTTERANCES[step_id]), step_id, str(result.get("tier", "")), str(result.get("reason", ""))]
		)

# ── 语音判定：串味的词不该过关 ────────────────────────────

func test_cross_words_are_not_accepted() -> void:
	var config := _load_config()
	for step_id in CROSS_WORDS.keys():
		var step := _step_by_id(config, step_id)
		assert_false(step.is_empty(), "配置里应有步骤 %s" % step_id)
		var result: Dictionary = LessonResponseMatcherScript.evaluate(str(CROSS_WORDS[step_id]), step.get("asr", {}))
		assert_false(
			_is_accepted(str(result.get("tier", ""))),
			"「%s」不该通过步骤 %s" % [str(CROSS_WORDS[step_id]), step_id]
		)

# ── 运行时全链路：跳过音频等待，把 9 步真的走一遍 ─────────────

func test_full_lesson_walkthrough_reaches_completion() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	assert_not_null(packed)
	var scene: Node = packed.instantiate()
	# 测试缝：headless 无音频后端，跳过 TTS 播放等待（见控制器的 test_skip_narration_wait）
	scene.test_skip_narration_wait = true
	scene.test_skip_scene_transition = true

	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var completed_state: int = ControllerScript.LessonState.COMPLETED
	var awaiting_state: int = ControllerScript.LessonState.AWAITING_VOICE
	var visited_voice_steps: Array[String] = []
	var started: int = Time.get_ticks_msec()
	var budget_ms: int = 45000

	# 一次只推进一个 voice 步，并且 await 掉推进协程，避免同一拍重复 accept。
	# auto 步（meet_classmates / gate_open）不会进入 AWAITING_VOICE，由步骤索引推进验证。
	while scene.state != completed_state and Time.get_ticks_msec() - started < budget_ms:
		if scene.state == awaiting_state:
			var step_id: String = str(scene.current_step.get("id", ""))
			if not visited_voice_steps.has(step_id):
				visited_voice_steps.append(step_id)
			await scene._accept_current_voice_step(str(NATURAL_UTTERANCES.get(step_id, "ok")))
		else:
			await get_tree().create_timer(0.05).timeout

	var elapsed: int = Time.get_ticks_msec() - started
	print("[walkthrough] elapsed_ms=%d state=%d voice_steps=%s words=%s" % [
		elapsed, scene.state, str(visited_voice_steps), str(scene.earned_words)
	])

	assert_eq(scene.state, completed_state, "整课走完后应进入 COMPLETED（elapsed=%dms）" % elapsed)
	assert_eq(visited_voice_steps.size(), 7, "7 个 voice 步都应被访问（visited=%s）" % str(visited_voice_steps))
	assert_eq(str(scene.current_step.get("id", "")), "gate_open", "结束时停在最后一步 gate_open")
	assert_eq(scene.earned_words.size(), 9, "9 个 reward_words 应全部解锁（实际=%s）" % str(scene.earned_words))
	assert_true(scene.earned_words.has("city"), "city 应解锁")
	assert_true(scene.earned_words.has("house"), "house 应解锁")

	var manager: Variant = scene._game_manager()
	if manager:
		assert_true(manager.completed_dialogues.has("changan_gate_01_complete"), "完成记账 completed_dialogues 应写入 changan_gate_01_complete")
		assert_true(manager.unlocked_areas.has("ChangAnMarketLesson02"), "next_unlock 应解锁 ChangAnMarketLesson02")
		assert_eq(GameManager.get_next_lesson(), "ChangAnMarketLesson02", "完成后应把下一课记进 GameManager，供客栈出发")

	if is_instance_valid(scene):
		remove_child(scene)
		scene.free()

func test_next_lesson_scene_is_registered() -> void:
	var config := _load_config()
	var next_id: String = str(config.get("next_unlock", ""))
	assert_eq(next_id, "ChangAnMarketLesson02", "情节 1 的下一课应是情节 2")
	assert_ne(GameManager.get_scene_path(next_id), "", "下一课必须在 GameManager.SCENE_PATHS 中注册")

func test_lesson_two_declares_unbuilt_next_lesson() -> void:
	var file := FileAccess.open("res://assets/resources/scene_configs/chang_an_market_lesson_02.json", FileAccess.READ)
	assert_not_null(file)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var next_id: String = str(parsed.get("next_unlock", ""))
	assert_eq(next_id, "ChangAnMarketLesson03", "情节 2 的下一课应是情节 3（尚未实现）")
	assert_eq(GameManager.get_scene_path(next_id), "", "未实现的下一课不应解析出路径，推进器应优雅停在完成态")
