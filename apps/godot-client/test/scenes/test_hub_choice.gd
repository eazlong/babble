extends GutTest

## 客栈 hub 复访的"二选一"契约：再次回到客栈时，玩家必须能自己选——继续主线（出发），
## 还是去词灵阁玩复习小游戏。
##
## 背景：hub 入口原先按存档状态单向派活——能量满只提出发、能量不足只提充能、
## 没有可玩下一情节时干脆不监听。三种写法都让"我就想去词灵阁玩"没有出口，
## 而 ADR 0003 §15 明确要求：阵法满、或后续情节未开放时，词灵阁仍可进入做加练。

const ControllerScript = preload("res://assets/scripts/scenes/MirageInnIntroductionController.gd")
const ControllerPath: String = "res://assets/scripts/scenes/MirageInnIntroductionController.gd"
const FLOWS_PATH: String = "res://assets/resources/dialogue_flows/inn_introduction.json"

const ZH_DEPART: String = "出发"
const ZH_LIBRARY: String = "词灵阁"

const CHOICE_FLOWS: Array[String] = [
	"inn_introduction.hub_choice_prompt",
	"inn_introduction.hub_choice_charge_prompt",
	"inn_introduction.hub_choice_practice_prompt",
]


func _controller_source() -> String:
	var file := FileAccess.open(ControllerPath, FileAccess.READ)
	assert_not_null(file, "controller 源码应能读取")
	if file == null:
		return ""
	var source := file.get_as_text()
	file.close()
	return source


func _flow(flow_id: String) -> Dictionary:
	var file := FileAccess.open(FLOWS_PATH, FileAccess.READ)
	assert_not_null(file, "inn_introduction.json 应能读取")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	for flow in parsed.get("flows", []):
		if flow is Dictionary and str(flow.get("flow_id", "")) == flow_id:
			return flow
	return {}


# ── 状态与提示词选择 ──────────────────────────────────────────────────

func test_hub_entry_state_is_the_choice_state() -> void:
	assert_true(
		ControllerScript.InnIntroState.has("HUB_AWAIT_CHOICE"),
		"hub 入口应有 HUB_AWAIT_CHOICE 状态"
	)

func test_old_single_track_depart_state_is_gone() -> void:
	var source := _controller_source()
	assert_false(
		source.contains("HUB_AWAIT_DEPART"),
		"单向出发状态不应残留：它正是'没有词灵阁出口'的旧写法"
	)
	assert_true(
		source.contains("await _enter_hub_choice()"),
		"hub 入口应先进入二选一"
	)

func test_choice_flow_when_both_paths_are_open() -> void:
	assert_eq(
		ControllerScript.hub_choice_flow_for(false, true, false),
		ControllerScript.HUB_CHOICE_FLOW,
		"能量满且有下一情节 → 通用二选一"
	)
	# 在途情节凭"已付费"免费续行：即使能量是 0，也不该退化成只提充能的单向提示。
	assert_eq(
		ControllerScript.hub_choice_flow_for(true, true, true),
		ControllerScript.HUB_CHOICE_FLOW,
		"有在途情节可续行 → 仍是二选一，不能被充能提示顶掉出发这条路"
	)

func test_choice_flow_asks_for_charge_when_departure_is_gated() -> void:
	assert_eq(
		ControllerScript.hub_choice_flow_for(false, true, true),
		ControllerScript.HUB_CHOICE_CHARGE_FLOW,
		"能量不足且有下一情节 → 充能提示（出发仍可被听到，只是会被引导去充能）"
	)

func test_choice_flow_keeps_library_open_without_next_lesson() -> void:
	assert_eq(
		ControllerScript.hub_choice_flow_for(false, false, false),
		ControllerScript.HUB_CHOICE_PRACTICE_FLOW,
		"没有可玩下一情节 → 仍要说话、仍要能进词灵阁加练，而不是沉默收场"
	)


# ── 提示词本身 ────────────────────────────────────────────────────────

func test_choice_flows_exist_and_are_feifei_spoken_and_bilingual() -> void:
	for flow_id in CHOICE_FLOWS:
		var flow: Dictionary = _flow(flow_id)
		assert_false(flow.is_empty(), "二选一提示应存在：%s" % flow_id)
		if flow.is_empty():
			continue
		assert_eq(str(flow.get("speaker", "")), "feifei", "%s 应由腓腓说（只有她可以用中文）" % flow_id)
		assert_eq(str(flow.get("voice", "")), "spirit", "%s 应用腓腓音色" % flow_id)
		var lines: Array = flow.get("lines", [])
		assert_true(lines.size() >= 1, "%s 至少要有一句" % flow_id)
		for line in lines:
			var text: Dictionary = line.get("text", {})
			assert_true(str(text.get("zh", "")).length() > 0, "%s 缺中文台词" % flow_id)
			assert_true(str(text.get("en", "")).length() > 0, "%s 缺英文台词" % flow_id)

func test_choice_prompts_teach_the_phrases_that_are_actually_recognized() -> void:
	var controller = ControllerScript.new()
	for flow_id in CHOICE_FLOWS:
		var flow: Dictionary = _flow(flow_id)
		if flow.is_empty():
			continue
		for line in flow.get("lines", []):
			var zh: String = str(line.get("text", {}).get("zh", ""))
			# 提示里出现的口令必须真被认得：教了"出发"却只认"Let's go"是最伤孩子的错。
			if zh.contains(ZH_DEPART):
				assert_true(controller._is_depart_call(zh), "%s 教了出发口令，matcher 却不认" % flow_id)
			if zh.contains(ZH_LIBRARY):
				assert_true(controller._is_library_entry_call(zh), "%s 教了词灵阁口令，matcher 却不认" % flow_id)
	controller.free()

func test_charge_prompt_reports_how_many_charges_are_missing() -> void:
	var flow: Dictionary = _flow("inn_introduction.hub_choice_charge_prompt")
	assert_false(flow.is_empty(), "充能提示应存在")
	if flow.is_empty():
		return
	var zh: String = str(flow["lines"][0].get("text", {}).get("zh", ""))
	var en: String = str(flow["lines"][0].get("text", {}).get("en", ""))
	assert_true(zh.contains("{missing}"), "中文充能提示应报出还差几格")
	assert_true(en.contains("{missing}"), "英文充能提示应报出还差几格")


# ── 两条意图互不吞并 ──────────────────────────────────────────────────

func test_choice_intents_are_disjoint() -> void:
	var controller = ControllerScript.new()
	assert_true(controller._is_depart_call("Let's go"), "出发口令应可识别")
	assert_true(controller._is_depart_call(ZH_DEPART), "中文出发口令应可识别")
	assert_true(controller._is_library_entry_call(ZH_LIBRARY), "词灵阁口令应可识别")
	assert_true(controller._is_library_entry_call("充能"), "充能口令应可识别")
	assert_false(controller._is_depart_call(ZH_LIBRARY), "说词灵阁不该被当成出发")
	assert_false(controller._is_library_entry_call(ZH_DEPART), "说出发不该被当成进词灵阁")
	controller.free()

func test_choice_candidates_follow_the_available_paths() -> void:
	var both: Array = ControllerScript.hub_choice_candidates(true)
	assert_true(both.has(ZH_DEPART), "能出发时候选集要含出发口令")
	assert_true(both.has(ZH_LIBRARY), "候选集永远要含词灵阁入口")
	var library_only: Array = ControllerScript.hub_choice_candidates(false)
	assert_true(library_only.has(ZH_LIBRARY), "没有可走的主线时词灵阁入口仍在")
	assert_false(library_only.has(ZH_DEPART), "没有可走的主线时不该把出发塞进封闭题（会误导 ASR）")
	assert_false(library_only.has("let's go"), "没有可走的主线时不该把英文出发塞进封闭题")


# ── 任务栏与失败重述文案 ──────────────────────────────────────────────

func test_choice_quest_text_lists_both_commands() -> void:
	var quest_zh: String = ControllerScript.loc("quest_hub_choice", "zh")
	assert_true(quest_zh.contains(ZH_DEPART), "任务栏要写出出发口令，实际=%s" % quest_zh)
	assert_true(quest_zh.contains(ZH_LIBRARY), "任务栏要写出词灵阁口令，实际=%s" % quest_zh)
	var quest_en: String = ControllerScript.loc("quest_hub_choice", "en")
	assert_true(quest_en.to_lower().contains("let's go"), "英文任务栏要写出出发口令，实际=%s" % quest_en)
	assert_true(quest_en.to_lower().contains("word spirit library"), "英文任务栏要写出词灵阁入口，实际=%s" % quest_en)

func test_practice_quest_text_offers_the_library_only() -> void:
	var quest_zh: String = ControllerScript.loc("quest_hub_choice_practice", "zh")
	assert_true(quest_zh.contains(ZH_LIBRARY), "没有下一情节时任务栏要指向词灵阁，实际=%s" % quest_zh)
	assert_false(quest_zh.contains(ZH_DEPART), "没有下一情节时不该再提出发，实际=%s" % quest_zh)

func test_retry_text_reminds_both_commands() -> void:
	var retry_zh: String = ControllerScript.loc("hub_choice_retry", "zh")
	assert_true(retry_zh.contains(ZH_DEPART), "没听清时要重述出发口令，实际=%s" % retry_zh)
	assert_true(retry_zh.contains(ZH_LIBRARY), "没听清时要重述词灵阁口令，实际=%s" % retry_zh)

func test_localized_keys_exist_in_both_languages() -> void:
	for key in ["quest_hub_choice", "quest_hub_choice_practice", "hub_choice_retry"]:
		assert_true(ControllerScript.loc(key, "zh").length() > 0, "%s 缺中文" % key)
		assert_true(ControllerScript.loc(key, "en").length() > 0, "%s 缺英文" % key)
	assert_eq(ControllerScript.loc("no_such_key", "zh"), "", "未知 key 应返回空串")


# ── 旧行为不该回来 ────────────────────────────────────────────────────

func test_hub_entry_never_goes_silent_without_listening() -> void:
	var start_hub: String = _function_body(_controller_source(), "func _start_hub()")
	assert_true(start_hub.length() > 0, "应能取到 _start_hub 的函数体")
	assert_false(
		start_hub.contains("hub_content_pending"),
		"'后续情节尚未开放'不能再直接收场——那等于把词灵阁的门也关了"
	)
	assert_true(
		start_hub.contains("_enter_hub_choice()"),
		"hub 入口必须落到二选一"
	)

## 截取一个函数的函数体（从签名到下一个顶层 func），用于"旧写法不许回来"的接线断言。
func _function_body(source: String, signature: String) -> String:
	var start: int = source.find(signature)
	if start < 0:
		return ""
	var rest: String = source.substr(start)
	var next_func: int = rest.find("\nfunc ", signature.length())
	return rest if next_func < 0 else rest.substr(0, next_func)
