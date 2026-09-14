# DialogueFlowLoader 单元测试
extends GutTest

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")

func test_loads_beginning_dialogue_flows():
	var loader: Variant = DialogueFlowLoaderScript.new()
	var ok: bool = loader.load_dialogue_flows()
	assert_true(ok, "beginning dialogue flow JSON 应能成功加载")
	assert_true(loader.has_flow("beginning.wake_greeting"))

func test_get_lines_returns_metadata_and_text():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.wake_greeting", "zh")

	# 开场拆成四拍：安抚与自我介绍 → 认主事实 → 原因悬念 → 才问名字。
	assert_eq(lines.size(), 4)
	assert_eq(lines[0]["key"], "feifei_greeting")
	assert_eq(lines[0]["speaker"], "feifei")
	assert_eq(lines[0]["voice"], "spirit")
	assert_true(str(lines[0]["text"]).contains("别怕"), "第一拍应先安抚玩家")
	assert_false(str(lines[0]["text"]).contains("你叫什么名字"), "第一拍不应问名字")

	assert_eq(lines[1]["key"], "feifei_greeting_recognition")
	assert_true(str(lines[1]["text"]).contains("客栈已经认你为主人"), "第二拍应说明客栈已认主")

	assert_eq(lines[2]["key"], "feifei_greeting_unknown_reason")
	assert_true(str(lines[2]["text"]).contains("我也不知道为什么"), "第三拍应保留原因悬念")

	assert_eq(lines[3]["key"], "feifei_greeting_outsider")
	assert_true(str(lines[3]["text"]).contains("你叫什么名字"), "第四拍才问名字")

func test_get_lines_replaces_named_placeholders():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.ask_special_name", "en", {
		"player_source_name": "小明",
		"special_language_name": "English",
	})

	assert_eq(lines.size(), 1)
	assert_true(str(lines[0]["text"]).contains("小明 is a good name"))
	assert_true(str(lines[0]["text"]).contains("English name"))
	assert_false(str(lines[0]["text"]).contains("{special_language_name}"))

func test_get_lines_returns_all_lines_in_flow():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.name_celebrate", "en", {
		"player_display_name": "Alice",
	})

	assert_eq(lines.size(), 2)
	assert_eq(lines[0]["text"], "Alice sounds wonderful. You must be wondering where this is.")
	assert_eq(lines[1]["key"], "feifei_okay_response")

func test_name_celebrate_no_longer_asks_unanswered_how_are_you():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	# 原来的 feifei_how_are_you 问了情绪却不接收回答（问完立刻被下一句自答），
	# 8 岁玩家会重复回答却没人理，因此移除该提问。
	var lines: Array[Dictionary] = loader.get_lines("beginning.name_celebrate", "zh", {
		"player_display_name": "Alice",
	})
	for line in lines:
		assert_false(str(line["text"]).contains("你今天感觉怎么样"),
			"不应再有问了不听的 how_are_you 提问")

func test_special_name_proposal_has_accept_and_decline_flows():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	# 提议名字后必须同时存在“接受”和“拒绝”两条路径，
	# 否则玩家说“不”会掉进 intent_not_matched 被重复提议，形成确认死循环。
	assert_true(loader.has_flow("beginning.accept_special_name"))
	assert_true(loader.has_flow("beginning.decline_special_name"))

	var declined: Array[Dictionary] = loader.get_lines("beginning.decline_special_name", "zh", {
		"special_language_name": "英语",
	})
	assert_eq(declined.size(), 1)
	assert_true(str(declined[0]["text"]).contains("你想要的英语名字"),
		"拒绝提议后应引导玩家自己给名字")
	assert_false(str(declined[0]["text"]).contains("{special_language_name}"),
		"占位符必须被替换")

func test_removed_walk_in_flows_are_gone():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	# 玩家已在客栈主人房醒来，不再有“看见客栈 / 走进客栈”演出。
	assert_false(loader.has_flow("beginning.inn_follow_feifei"), "跟随进门 flow 应删除")
	assert_false(loader.has_flow("beginning.inn_transition"), "进门转场 flow 应删除")

func test_inn_reveal_is_in_room_not_outside():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.inn_reveal", "zh")
	assert_eq(lines.size(), 2)
	assert_true(str(lines[0]["text"]).contains("你现在就在蜃影客栈里"), "客栈解释应发生在室内")
	assert_false(str(lines[0]["text"]).contains("看到前面的客栈"), "不应再有外景揭示")
	assert_true(str(lines[1]["text"]).contains("客栈就认了你"), "最后应点回认主悬念")

func test_six_artifacts_has_visual_anchor():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	# “六”是核心收集目标，必须给一个能看见的锚点（六道光）。
	var en_lines: Array[Dictionary] = loader.get_lines("beginning.distant_continents", "en")
	assert_true(str(en_lines[0]["text"]).contains("Six lights"),
		"英文应给出可见的“六道光”锚点")
	var zh_lines: Array[Dictionary] = loader.get_lines("beginning.distant_continents", "zh")
	assert_true(str(zh_lines[0]["text"]).contains("六道光"),
		"中文应给出可见的“六道光”锚点")

func test_mirage_inn_intro_uses_owner_room_and_hall_flows():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	assert_true(loader.has_flow("inn_introduction.owner_room"), "导览第一站应为 owner_room")
	assert_true(loader.has_flow("inn_introduction.hall"), "大厅 flow 应改名并保留")
	assert_false(loader.has_flow("inn_introduction.entry"), "旧 entry flow 应退役")
	assert_false(loader.has_flow("inn_introduction.player_room"), "旧 player_room flow 应退役")

	var lines: Array[Dictionary] = loader.get_lines("inn_introduction.owner_room", "zh")
	assert_eq(lines.size(), 3)
	assert_true(str(lines[0]["text"]).contains("你醒来的地方"), "owner_room 应从醒来地点接续")
	assert_true(loader.has_flow("inn_introduction.hub_depart_prompt"), "hub 出发提示 flow 应存在")
	assert_true(loader.has_flow("inn_introduction.hub_depart_ack"), "hub 出发确认 flow 应存在")
	assert_true(loader.has_flow("inn_introduction.hub_stay"), "hub 无下一课时停留 flow 应存在")

func test_mirage_inn_intro_flow_order_matches_canon():
	var file := FileAccess.open("res://assets/resources/dialogue_flows/inn_introduction.json", FileAccess.READ)
	assert_not_null(file, "inn_introduction.json 应能打开")
	var data: Variant = JSON.parse_string(file.get_as_text())
	assert_true(data is Dictionary, "inn_introduction.json 根应为对象")
	var ids: Array[String] = []
	for flow in data["flows"]:
		ids.append(str(flow["flow_id"]))
	var expected: Array[String] = [
		"inn_introduction.owner_room",
		"inn_introduction.bookshelf_voice_prompt",
		"inn_introduction.bookshelf_opened",
		"inn_introduction.word_spirit_library",
		"inn_introduction.wardrobe_preview",
		"inn_introduction.hall",
		"inn_introduction.formation_room",
		"inn_introduction.guest_room_preview",
		"inn_introduction.summary",
		"inn_introduction.hub_depart_prompt",
		"inn_introduction.hub_depart_ack",
		"inn_introduction.hub_stay",
	]
	assert_eq(ids, expected, "导览 flow 顺序应为主人房→书柜→书阁→衣橱→大厅→阵法→客房→总结")

func test_get_lines_falls_back_to_english_for_unknown_language():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.wake_greeting", "fr")

	# 未知语言回退英文：四拍都应有英文文本且不含占位符残留。
	assert_eq(lines.size(), 4)
	assert_true(str(lines[0]["text"]).contains("awake"))
	assert_true(str(lines[3]["text"]).begins_with("You're an outsider"))

func test_unknown_flow_returns_empty_lines():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("missing.flow", "en")

	assert_eq(lines.size(), 0)

func test_duplicate_flow_id_is_rejected():
	var dir_path: String = "user://dialogue_flow_loader_duplicate_test/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	_write_file(dir_path + "a.json", _duplicate_flow_json("test.flow", "One"))
	_write_file(dir_path + "b.json", _duplicate_flow_json("test.flow", "Two"))

	var loader: Variant = DialogueFlowLoaderScript.new()
	var ok: bool = loader.load_dialogue_flows(dir_path)

	assert_false(ok, "重复 flow_id 应让加载结果标记失败")
	assert_true(loader.has_flow("test.flow"), "第一个 flow 仍应保留")
	assert_true(loader.get_errors().size() > 0)
	var lines: Array[Dictionary] = loader.get_lines("test.flow", "en")
	assert_eq(lines[0]["text"], "One")

func test_invalid_flow_or_line_is_skipped_without_file_load_failure():
	var dir_path: String = "user://dialogue_flow_loader_invalid_line_test/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	_write_file(dir_path + "mixed.json", _mixed_valid_and_invalid_json())

	var loader: Variant = DialogueFlowLoaderScript.new()
	var ok: bool = loader.load_dialogue_flows(dir_path)

	assert_true(ok, "坏 flow/line 应被跳过，不应让整个文件加载失败")
	assert_true(loader.get_errors().size() > 0)
	assert_true(loader.has_flow("test.valid"))
	var lines: Array[Dictionary] = loader.get_lines("test.valid", "en")
	assert_eq(lines.size(), 1)
	assert_eq(lines[0]["text"], "Valid")

func _write_file(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "测试文件应能写入: %s" % path)
	if file:
		file.store_string(content)
		file.close()

func _duplicate_flow_json(flow_id: String, text: String) -> String:
	return JSON.stringify({
		"schema_version": 1,
		"scene_id": "test",
		"flows": [
			{
				"flow_id": flow_id,
				"speaker": "feifei",
				"voice": "spirit",
				"lines": [
					{
						"key": "line",
						"text": {
							"en": text
						}
					}
				]
			}
		]
	})

func _mixed_valid_and_invalid_json() -> String:
	return JSON.stringify({
		"schema_version": 1,
		"scene_id": "test",
		"flows": [
			{
				"flow_id": "test.valid",
				"speaker": "feifei",
				"voice": "spirit",
				"lines": [
					{
						"key": "valid_line",
						"text": {
							"en": "Valid"
						}
					},
					{
						"key": "invalid_line"
					}
				]
			},
			{
				"flow_id": "test.invalid"
			}
		]
	})
