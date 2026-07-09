# test_word_highlighter.gd
# GUT 测试用例 — WordHighlighter
# 测试分词高亮 BBCode 生成、逐词高亮序列、关键词提取

extends GutTest

const WordHighlighter = preload("res://assets/scripts/components/WordHighlighter.gd")

# ── build_highlighted ──

func test_highlight_all_words():
	var result: String = WordHighlighter.build_highlighted("water the red flower")
	assert_true(result.contains("[color=yellow]"), "应包含黄色高亮标签")
	assert_true(result.contains("[b]water[/b]"), "water 应加粗")
	assert_true(result.contains("[b]the[/b]"), "the 应加粗")
	assert_true(result.contains("[b]red[/b]"), "red 应加粗")
	assert_true(result.contains("[b]flower[/b]"), "flower 应加粗")

func test_highlight_single_word():
	var result: String = WordHighlighter.build_highlighted("water the red flower", 0)
	# 第一个词高亮，其余不
	assert_true(result.contains("[b]water[/b]"), "第 0 个词 water 应高亮")
	# the/red/flower 不应包含 [b]
	assert_false(result.contains("[b]the[/b]"), "the 不应高亮")
	assert_false(result.contains("[b]red[/b]"), "red 不应高亮")

func test_highlight_middle_word():
	var result: String = WordHighlighter.build_highlighted("water the red flower", 2)
	assert_true(result.contains("[b]red[/b]"), "第 2 个词 red 应高亮")
	assert_false(result.contains("[b]water[/b]"), "water 不应高亮")

func test_highlight_last_word():
	var result: String = WordHighlighter.build_highlighted("water the red flower", 3)
	assert_true(result.contains("[b]flower[/b]"), "最后一个词 flower 应高亮")
	assert_false(result.contains("[b]water[/b]"), "water 不应高亮")

func test_highlight_preserves_spaces():
	var result: String = WordHighlighter.build_highlighted("hello world")
	# 单词之间应有一个空格
	assert_true(result.contains(" "), "单词间应有空格")

func test_highlight_single_word_sentence():
	var result: String = WordHighlighter.build_highlighted("hello")
	assert_true(result.contains("[b]hello[/b]"), "单字词应正确高亮")

func test_highlight_empty_string():
	var result: String = WordHighlighter.build_highlighted("")
	# 空字符串不崩溃
	assert_true(result != null or result == "", "空字符串不崩溃")

func test_highlight_negative_index_means_all():
	var all_result: String = WordHighlighter.build_highlighted("water the red flower", -1)
	var default_result: String = WordHighlighter.build_highlighted("water the red flower")
	assert_eq(all_result, default_result, "highlight_index=-1 应等同于默认（全部高亮）")

# ── build_highlight_sequence ──

func test_highlight_sequence_length():
	var seq: Array[String] = WordHighlighter.build_highlight_sequence("water the red flower")
	assert_eq(seq.size(), 4, "4 个词应产生 4 帧高亮序列")

func test_highlight_sequence_each_frame_highlights_one():
	var seq: Array[String] = WordHighlighter.build_highlight_sequence("water the red flower")
	# 第 0 帧：water 高亮
	assert_true(seq[0].contains("[b]water[/b]"), "第 0 帧 water 高亮")
	assert_false(seq[0].contains("[b]the[/b]"), "第 0 帧 the 不高亮")
	# 第 2 帧：red 高亮
	assert_true(seq[2].contains("[b]red[/b]"), "第 2 帧 red 高亮")
	assert_false(seq[2].contains("[b]water[/b]"), "第 2 帧 water 不高亮")

func test_highlight_sequence_single_word():
	var seq: Array[String] = WordHighlighter.build_highlight_sequence("hello")
	assert_eq(seq.size(), 1)
	assert_true(seq[0].contains("[b]hello[/b]"))

# ── extract_keywords ──

func test_extract_keywords_skips_articles():
	var result: String = WordHighlighter.extract_keywords("water the red flower")
	assert_true(result.contains("water"), "应包含 water")
	assert_true(result.contains("red"), "应包含 red")
	assert_true(result.contains("flower"), "应包含 flower")
	assert_false(result.contains("the"), "应跳过 the")

func test_extract_keywords_custom_skip():
	var result: String = WordHighlighter.extract_keywords("water the red flower", ["water"])
	assert_false(result.contains("water"), "自定义跳过 water")
	assert_true(result.contains("the"), "the 不在跳过列表中")

func test_extract_keywords_empty_skip():
	var result: String = WordHighlighter.extract_keywords("hello world", [])
	assert_eq(result, "hello world", "不跳过任何词应保留完整句子")

# ── BBCode 格式正确性 ──

func test_bbcode_tags_balanced():
	var result: String = WordHighlighter.build_highlighted("hello world")
	# [color=yellow] 和 [/color] 数量应相等
	var open_count: int = result.count("[color=yellow]")
	var close_count: int = result.count("[/color]")
	assert_eq(open_count, close_count, "[color] 标签应平衡")

	# [b] 和 [/b] 数量应相等
	var b_open: int = result.count("[b]")
	var b_close: int = result.count("[/b]")
	assert_eq(b_open, b_close, "[b] 标签应平衡")
