extends GutTest

## 序章英语名阶段的**委托（delegate）识别兜底**回归测试。
##
## 背景（用户报告）：流程走到英语名那一步，回复「帮我起一个吧」时意图没被识别到，
## 客户端把整句话当成孩子的英语名继续推进（并落盘）。
## 根因是两层：① 该步的 ASR 语言提示被设成 en，中文语音交给强制英语解码；
## ② 模型偶尔把委托句判成 provide/off_topic，而 provide 路径会把原话当名字。
##
## 本文件锁住修复后的契约：
## 1. `_is_delegation_utterance` 的判定表（纯函数）；
## 2. 模型误判（provide + extracted=委托原话 / off_topic）时仍必须走提议分支；
## 3. 真正的英语名与提议态表态不受影响；
## 4. 该步的 ASR 语言提示是双语 cn_en，不再按"期望答案语言"推成 en。

const BeginningFPControllerScript = preload("res://assets/scripts/scenes/BeginningFPController.gd")

## 测试替身脚本：拦掉一切会走 HTTP / 剧情推进 / UI 的方法，
## 只保留被测的路由判定 + 槽位状态机。
## NOTE: 替身**刻意不接进场景树**——控制器 `_ready()` 会用 `$FeifeiLayer` 等路径解析
## @onready 变量，而挂真实 FeifeiBody 会触发一堆 Bone2D 引擎警告（GUT 把 engine error
## 记为 Unexpected Error 并判失败），换成裸节点又会报类型错误。挑哪条路都脏，
## 所以这里让替身留在树外，只测纯函数与槽位状态机，飞飞相关方法全部被替身覆盖。
const ControllerDoubleScript = preload("res://test/scenes/test_beginning_fp_special_name_delegate_double.gd")


func _new_double():
	return ControllerDoubleScript.new()


func _asr_result(intent: String, text: String, extracted_name: String = "") -> Dictionary:
	var postprocess := {
		"corrected_text": text,
		"intent": intent,
		"intent_matched": intent == "provide",
		"extracted": {},
	}
	if not extracted_name.is_empty():
		postprocess["extracted"] = {"name": extracted_name}
	return {"text": text, "postprocess": postprocess}


func _special_name_controller():
	var controller = _new_double()
	controller.state = controller.PrologueState.AWAIT_SPECIAL_NAME
	controller.special_name_slot_state = controller.SLOT_AWAITING
	return controller


# --- 1. 判定表（纯函数） ---------------------------------------------------

func test_delegation_utterance_matches_chinese_requests() -> void:
	var controller = _new_double()
	for phrase in ["帮我起一个吧", "你帮我起一个吧", "帮我取一个", "帮我选一个", "你帮我", "随便选一个", "你决定吧", "你决定", "帮我想一个吧"]:
		assert_true(controller._is_delegation_utterance(phrase), "『%s』应判为委托" % phrase)
	controller.free()


func test_delegation_utterance_matches_english_requests() -> void:
	var controller = _new_double()
	for phrase in ["you pick one", "You choose for me", "you decide", "pick one", "up to you", "whatever", "no idea"]:
		assert_true(controller._is_delegation_utterance(phrase), "『%s』应判为委托" % phrase)
	controller.free()


func test_delegation_utterance_rejects_names_and_empty() -> void:
	var controller = _new_double()
	# 关键：英文必须整词匹配，否则名字里的片段会误命中（与 DECLINE_MARKERS_EN 同理）。
	for phrase in ["Carl", "Mia", "Wendy", "Leo", "Luna", "Alice", "", "   "]:
		assert_false(controller._is_delegation_utterance(phrase), "『%s』不应判为委托" % phrase)
	controller.free()


func test_delegation_utterance_does_not_capture_self_service() -> void:
	var controller = _new_double()
	# 玩家说"自己取"是 provide 意图，不能被兜底抢走。
	assert_false(
		controller._is_delegation_utterance("我自己取一个吧"),
		"『我自己取一个吧』是玩家自己取名，不是委托"
	)
	assert_false(
		controller._is_delegation_utterance("我起好了，就叫 Leo"),
		"已经给出名字的句子不应判为委托"
	)
	controller.free()


# --- 2. 模型误判时仍必须提议 ------------------------------------------------

func test_model_off_topic_delegate_utterance_still_proposes() -> void:
	var controller = _special_name_controller()

	await controller._handle_special_name_asr_result(_asr_result("off_topic", "帮我起一个吧"))

	assert_eq(controller.propose_count, 1, "模型判 off_topic 时，委托原话也应触发提议")
	assert_eq(controller.handle_name_count, 0, "委托原话绝不能被当成英语名落定")
	controller.free()


func test_model_provide_with_delegate_utterance_still_proposes() -> void:
	var controller = _special_name_controller()

	# 这是最危险的一条：模型判 provide，而 corrected_text 是委托原话。
	await controller._handle_special_name_asr_result(_asr_result("provide", "帮我起一个吧"))

	assert_eq(controller.propose_count, 1, "provide + 委托原话不应进入取名路径")
	assert_eq(controller.handle_name_count, 0, "provide + 委托原话绝不能把原话当英语名")
	assert_eq(
		controller.special_name_slot_state,
		controller.SLOT_PROPOSED,
		"提议后槽位应进入 proposed"
	)
	controller.free()


func test_model_provide_with_chinese_extracted_name_still_proposes() -> void:
	var controller = _special_name_controller()

	# 覆盖模型**回填**委托原话的情形：extracted.name 不是英语名形状。
	await controller._handle_special_name_asr_result(
		_asr_result("provide", "你帮我取一个", "你帮我取一个")
	)

	assert_eq(controller.propose_count, 1, "中文 extracted 值不应被当成英语名")
	assert_eq(controller.handle_name_count, 0, "非英语名的 extracted 值绝不能落定为名字")
	controller.free()


# --- 3. 正常路径不受影响 ----------------------------------------------------

func test_delegate_label_proposes_from_pool() -> void:
	var controller = _special_name_controller()

	await controller._handle_special_name_asr_result(_asr_result("delegate", "随便选一个"))

	assert_eq(controller.propose_count, 1, "delegate 标签应触发提议")
	assert_true(
		controller.SPECIAL_NAME_POOL.has(controller.proposed_special_name),
		"提议值必须来自本地值池"
	)
	assert_eq(controller.special_name_slot_state, controller.SLOT_PROPOSED, "槽位应进入 proposed")
	assert_eq(controller.start_listen_count, 1, "提议后必须重新开始录音，否则玩家没机会回答")
	controller.free()


func test_english_name_provide_still_fills_slot() -> void:
	var controller = _special_name_controller()

	await controller._handle_special_name_asr_result(_asr_result("provide", "Leo", "Leo"))

	assert_eq(controller.handle_name_count, 1, "英语名应照常落定")
	assert_eq(controller.handled_name, "Leo", "落定的名字应是 extracted.name")
	assert_eq(controller.propose_count, 0, "正常取名不应触发提议")
	controller.free()


func test_proposed_state_delegation_does_not_repropose_via_fallback() -> void:
	var controller = _special_name_controller()
	controller.special_name_slot_state = controller.SLOT_PROPOSED
	controller.proposed_special_name = "Carl"

	# 提议态下，"随便" 是对提议的表态，交给 _classify_proposal_reaction，不由兜底抢走。
	await controller._handle_special_name_asr_result(_asr_result("provide", "随便"))

	assert_eq(controller.propose_count, 0, "提议态的兜底分支不应触发")
	controller.free()


# --- 4. ASR 语言提示 --------------------------------------------------------

func test_special_name_state_asks_asr_for_bilingual_hint() -> void:
	var controller = _special_name_controller()
	assert_eq(
		controller._get_asr_language_for_state(),
		"cn_en",
		"英语名这一步必须同时能识别中文求助与英语名，不能按期望答案语言推成 en"
	)
	assert_eq(
		GameManager.BILINGUAL_ASR_LANGUAGE_CODE,
		"cn_en",
		"双语提示取值必须与 voice-service 的既有取值一致"
	)
	controller.free()


func test_source_name_state_keeps_chinese_hint() -> void:
	var controller = _new_double()
	controller.state = controller.PrologueState.AWAIT_SOURCE_NAME
	assert_eq(
		controller._get_asr_language_for_state(),
		GameManager.SOURCE_LANGUAGE_CODE,
		"中文名那一步仍按源语言识别"
	)
	controller.free()
