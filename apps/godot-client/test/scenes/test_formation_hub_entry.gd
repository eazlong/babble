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


## whisper 对普通话口令经常输出繁体，而 LIBRARY_ENTRY_MARKERS 只有简体。
## 漏了归一的话，postprocess 一旦没接上就被判 wrong_answer 卡在二选一。
func test_library_entry_matcher_normalizes_traditional_variants() -> void:
	var c = ControllerScript.new()
	assert_true(c._is_library_entry_call("詞靈閣"), "繁体词灵阁应命中")
	assert_true(c._is_library_entry_call("書閣"), "繁体书阁应命中")
	assert_true(c._is_library_entry_call("詞靈書閣"), "繁体词灵书阁应命中")
	assert_true(c._is_library_entry_call("我要去詞靈閣玩小遊戲"), "繁体整句应命中")
	assert_false(c._is_library_entry_call("出發"), "繁体出发不该被当成进词灵阁")
	c.free()


## 归一只解决「用字是繁体」，**不解决同音误听**——这里把边界钉死，免得日后
## 有人以为 matcher 已经全能、把 postprocess 的 candidate_answers 拆了。
## 输入是 pa_19_hub_library.wav 的真实原始 ASR（player_answers.json →
## answers[hub_library].asr_text）：whisper 把「词灵」听成「慈陵」。
## 这一条必须靠 voice-service postprocess（candidate_answers 白名单）纠回来，
## 归一后仍是「慈陵阁」，matcher 单靠自己认不出。
func test_library_entry_matcher_alone_cannot_fix_homophone_mishearing() -> void:
	var c = ControllerScript.new()
	assert_false(
		c._is_library_entry_call("我要去慈陵閣玩小遊戲"),
		"同音误听（慈陵→词灵）不该被 matcher 认成命中：它靠的是 postprocess"
	)
	c.free()
