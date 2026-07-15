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

	assert_eq(lines.size(), 1)
	assert_eq(lines[0]["key"], "feifei_greeting")
	assert_eq(lines[0]["speaker"], "feifei")
	assert_eq(lines[0]["voice"], "spirit")
	assert_true(str(lines[0]["text"]).contains("你叫什么名字"))

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

	assert_eq(lines.size(), 3)
	assert_eq(lines[0]["text"], "Alice sounds wonderful. You must be wondering where this is.")
	assert_eq(lines[1]["key"], "feifei_how_are_you")
	assert_eq(lines[2]["key"], "feifei_okay_response")

func test_get_lines_falls_back_to_english_for_unknown_language():
	var loader: Variant = DialogueFlowLoaderScript.new()
	loader.load_dialogue_flows()

	var lines: Array[Dictionary] = loader.get_lines("beginning.wake_greeting", "fr")

	assert_eq(lines.size(), 1)
	assert_true(str(lines[0]["text"]).begins_with("Hello"))

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
