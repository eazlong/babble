extends GutTest

## ADR-0009 客户端契约扩展的回归测试。
##
## 覆盖三件事：
## 1. 提议态表态判定表（accept/reject 精确标签 + 文本标记兜底）；
## 2. rule_010 的客户端门控（只认 matched_rule，不拿 intent 做判定）；
## 3. 口令标记表与门控的职责边界。
##
## 与 test_beginning_fp_special_name_delegate.gd / test_beginning_fp_resume.gd 分开，
## 便于本次契约变更独立回溯。

const BeginningFPControllerScript = preload("res://assets/scripts/scenes/BeginningFPController.gd")

const RETRACTION_RULE: String = "retraction_after_target"


func _new_controller():
	return BeginningFPControllerScript.new()


func _reaction(controller, intent: String, text: String) -> int:
	return controller._classify_proposal_reaction(intent, text)


# --- 提议态表态判定表：精确标签 > 文本兜底 ---

func test_proposal_reaction_accept_label_is_accept() -> void:
	var controller = _new_controller()
	assert_eq(
		_reaction(controller, "accept", "好"),
		controller.ProposalReaction.ACCEPT,
		"accept 标签应直接判为接受"
	)
	controller.free()


func test_proposal_reaction_reject_label_is_decline_without_markers() -> void:
	var controller = _new_controller()
	# 关键：原话不含任何拒绝标记，只有 reject 标签能识别出来。
	assert_eq(
		_reaction(controller, "reject", "\u968f\u4fbf"),
		controller.ProposalReaction.DECLINE,
		"reject 标签应直接判为拒绝，即使原话没有拒绝标记"
	)
	controller.free()


func test_proposal_reaction_falls_back_to_text_markers_for_legacy_server() -> void:
	var controller = _new_controller()
	# 旧服务端只发 provide/off_topic：没有 reject 标签时仍必须能识别拒绝，
	# 否则会退回"我说不好→她再问一次"的死循环。
	assert_eq(
		_reaction(controller, "provide", "no"),
		controller.ProposalReaction.DECLINE,
		"provide + 拒绝原话应判为拒绝（兼容旧服务端）"
	)
	assert_eq(
		_reaction(controller, "off_topic", "\u6362\u4e00\u4e2a"),
		controller.ProposalReaction.DECLINE,
		"off_topic + 更换原话应判为拒绝（兼容旧服务端）"
	)
	controller.free()


func test_proposal_reaction_provide_with_text_is_accept() -> void:
	var controller = _new_controller()
	assert_eq(
		_reaction(controller, "provide", "Carl"),
		controller.ProposalReaction.ACCEPT,
		"提议态下 provide + 有内容应判为接受提议"
	)
	controller.free()


func test_proposal_reaction_empty_answer_is_not_understood() -> void:
	var controller = _new_controller()
	assert_eq(
		_reaction(controller, "off_topic", ""),
		controller.ProposalReaction.NOT_UNDERSTOOD,
		"空答案既不是接受也不是拒绝"
	)
	assert_eq(
		_reaction(controller, "provide", ""),
		controller.ProposalReaction.NOT_UNDERSTOOD,
		"provide 但无内容不应落定槽位"
	)
	assert_eq(
		_reaction(controller, "delegate", ""),
		controller.ProposalReaction.NOT_UNDERSTOOD,
		"delegate 由调用方在更早分支处理，不应落到表态表"
	)
	controller.free()


func test_proposal_reaction_name_containing_no_is_not_decline() -> void:
	var controller = _new_controller()
	# 既有约束：英文整词匹配，否则 Nolan/Nora 会被当成 "no"。
	assert_eq(
		_reaction(controller, "provide", "Nolan"),
		controller.ProposalReaction.ACCEPT,
		"Nolan 不应被当成拒绝"
	)
	controller.free()


# --- rule_010 客户端门控 ---

func test_retraction_gate_blocks_on_rule_010_verdict() -> void:
	var controller = _new_controller()
	assert_true(
		controller._is_retraction_downgrade({
			"postprocess": {"intent": "off_topic", "matched_rule": RETRACTION_RULE},
		}),
		"规则层明确判定 retraction_after_target 时应拦截续行"
	)
	controller.free()


func test_retraction_gate_ignores_bare_off_topic() -> void:
	var controller = _new_controller()
	# 这是本门控刻意保守的地方：只看 intent 会把模型误判的合法口令句也拦下来，
	# 而续行被拦的后果是玩家卡在主人房。
	assert_false(
		controller._is_retraction_downgrade({"postprocess": {"intent": "off_topic"}}),
		"仅有 off_topic 无判据时不得拦截"
	)
	assert_false(
		controller._is_retraction_downgrade({
			"postprocess": {"intent": "provide", "matched_rule": "some_other_rule"},
		}),
		"其它规则不得影响续行"
	)
	assert_false(
		controller._is_retraction_downgrade({"text": "lets go"}),
		"缺少 postprocess 时应放行（规则层未接入 = 零行为变更）"
	)
	controller.free()


func test_retraction_gate_accepts_null_matched_rule() -> void:
	var controller = _new_controller()
	assert_false(
		controller._is_retraction_downgrade({"postprocess": {"intent": "provide", "matched_rule": null}}),
		"null 判据不得被当成命中"
	)
	controller.free()


func test_resume_marker_still_matches_superset_utterance() -> void:
	var controller = _new_controller()
	# 口令表按包含匹配，所以"命中口令 + 后续撤回"这种句子会被口令表放行——
	# 这正是 rule_010 门控存在的理由（本用例固化现状，门控负责兜住）。
	assert_true(controller._is_resume_call("let's go... \u7b49\u4e00\u4e0b"), "标记表按包含匹配命中口令")
	assert_false(controller._is_resume_call("bookshelf"), "无关话语不应命中口令")
	controller.free()
