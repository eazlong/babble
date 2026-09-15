extends GutTest

const ControllerScript = preload("res://assets/scripts/scenes/MirageInnIntroductionController.gd")

func test_library_entry_matcher_accepts_expected_phrases() -> void:
	var c = ControllerScript.new()
	assert_true(c._is_library_entry_call("\u8bcd\u7075\u9601"))
	assert_true(c._is_library_entry_call("\u4e66\u9601"))
	assert_true(c._is_library_entry_call("\u8bcd\u7075\u4e66\u9601"))
	assert_true(c._is_library_entry_call("\u5145\u80fd"))
	assert_true(c._is_library_entry_call("library"))
	assert_true(c._is_library_entry_call("word spirit"))
	assert_false(c._is_library_entry_call("let us go"))
	c.free()


func test_library_entry_candidates_include_all_accepted_phrases() -> void:
	var c = ControllerScript.new()
	var candidates: Array = c._library_entry_candidates()
	assert_true(candidates.has("\u8bcd\u7075\u9601"))
	assert_true(candidates.has("\u4e66\u9601"))
	assert_true(candidates.has("\u8bcd\u7075\u4e66\u9601"))
	assert_true(candidates.has("\u5145\u80fd"))
	assert_true(candidates.has("library"))
	c.free()
