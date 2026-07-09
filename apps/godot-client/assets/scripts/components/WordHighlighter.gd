## 分词高亮组件
##
## 将句子分词并生成 BBCode 高亮文本
## 用于浇花教学 scaffolded 发音学习
##
class_name WordHighlighter
extends RefCounted

## 生成高亮 BBCode，highlight_index 指定当前高亮词（-1 为全部高亮）
static func build_highlighted(sentence: String, highlight_index: int = -1) -> String:
	var words := sentence.split(" ")
	var bbcode := ""
	for i in words.size():
		if i == highlight_index or highlight_index == -1:
			bbcode += "[color=yellow][b]%s[/b][/color]" % words[i]
		else:
			bbcode += words[i]
		if i < words.size() - 1:
			bbcode += " "
	return bbcode

## 逐词高亮序列（用于慢速跟读时的逐词高亮动画）
static func build_highlight_sequence(sentence: String) -> Array[String]:
	var words := sentence.split(" ")
	var frames: Array[String] = []
	for i in words.size():
		frames.append(build_highlighted(sentence, i))
	return frames

## 提取关键词（用于降级提示）
static func extract_keywords(sentence: String, skip_words: Array[String] = ["the", "a", "an", "is", "to"]) -> String:
	var words := sentence.split(" ")
	var keywords: Array[String] = []
	for word in words:
		if not skip_words.has(word.to_lower()):
			keywords.append(word)
	return " ".join(keywords)
