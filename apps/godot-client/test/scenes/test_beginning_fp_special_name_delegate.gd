extends GutTest

const BeginningFPControllerScript = preload("res://assets/scripts/scenes/BeginningFPController.gd")

func test_special_name_context_includes_delegatable_slot() -> void:
	var controller = BeginningFPControllerScript.new()
	controller.state = controller.PrologueState.AWAIT_SPECIAL_NAME

	var slot: Dictionary = controller._build_special_name_slot(GameManager.SPECIAL_LANGUAGE_NAME)

	assert_eq(slot.get("delegatable", false), true, "英语名槽位应标记为可委托")
	assert_true(slot.get("value_pool", []).has(GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME), "值池应包含默认英语名")
	assert_eq(slot.get("pick_strategy", ""), "exclude_recent", "应声明排除近期提议的挑选策略")
	assert_eq(slot.get("slot_state", ""), controller.SLOT_AWAITING, "初始槽位状态应为awaiting")

func test_special_name_context_keeps_name_pool_out_of_candidate_answers() -> void:
	var controller = BeginningFPControllerScript.new()
	controller.state = controller.PrologueState.AWAIT_SPECIAL_NAME

	var context: Dictionary = controller._build_asr_context_for_state()

	assert_false(context.get("candidate_answers", []).has(GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME), "开放姓名槽位不应把值池塞进candidate_answers")

func test_special_name_context_includes_proposed_value() -> void:
	var controller = BeginningFPControllerScript.new()
	controller.state = controller.PrologueState.AWAIT_SPECIAL_NAME
	controller.special_name_slot_state = controller.SLOT_PROPOSED
	controller.proposed_special_name = "Carl"

	var slot: Dictionary = controller._build_special_name_slot(GameManager.SPECIAL_LANGUAGE_NAME)

	assert_eq(slot.get("slot_state", ""), controller.SLOT_PROPOSED, "提议状态应随ASR上下文传递")
	assert_eq(slot.get("proposed_value", ""), "Carl", "当前提议值应随ASR上下文传递")

func test_pick_special_name_candidate_excludes_recent_proposals() -> void:
	var controller = BeginningFPControllerScript.new()
	controller.recent_proposed_special_names = [GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME]

	var picked := controller._pick_special_name_candidate()

	assert_ne(picked, GameManager.DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME, "仍有未提议名字时不应重复最近提议")
	assert_true(controller.SPECIAL_NAME_POOL.has(picked), "挑选结果必须来自本地值池")
