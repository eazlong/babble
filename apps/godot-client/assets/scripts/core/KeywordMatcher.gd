class_name KeywordMatcher
extends RefCounted

## 关键词匹配器
## 实现 required（AND逻辑）和 optional（OR逻辑加分）关键词匹配
## 符合 ADR-0009 KeywordMatcher 规范

## 权重常量（来自 GDD Tuning Knobs）
const OPTIONAL_BONUS_PER_WORD: float = 0.1
const MAX_OPTIONAL_BONUS: float = 0.3

## 空关键词匹配的基础分（当没有required关键词时）
const BASE_SCORE_NO_REQUIRED: float = 0.0


## 主匹配接口
func match_keywords(
	text: String,
	required_keywords: Array[String],
	optional_keywords: Array[String]
) -> float:
	"""
	关键词匹配：required（AND逻辑）+ optional（OR逻辑加分）

	Args:
		text: 预处理后的输入文本
		required_keywords: 必须全部出现的关键词列表（AND逻辑）
		optional_keywords: 可选关键词列表，每个匹配给予额外加分

	Returns:
		匹配得分 (0.0 - 1.0+，但通常不超过 1.3)
		- 如果有required_keywords：必须全部匹配，否则返回0
		- 如果没有required_keywords：基于optional匹配给予基础分
	"""
	# 边界情况：空文本
	if text.is_empty():
		return 0.0

	# 将文本转换为词集合（O(n) 一次性构建，O(1) 查找）
	var text_words: Dictionary = _build_word_set(text)

	# Required 关键词匹配（AND逻辑）
	var required_score: float = _match_required_keywords(required_keywords, text_words)

	# 如果有 required 但未全部匹配，直接返回 0
	if required_keywords.size() > 0 and required_score < 1.0:
		return 0.0

	# Optional 关键词匹配（OR逻辑，加分）
	var optional_bonus: float = _calculate_optional_bonus(optional_keywords, text_words)

	# 计算最终得分
	var final_score: float = required_score + optional_bonus
	return clampf(final_score, 0.0, 1.0 + MAX_OPTIONAL_BONUS)


## 检查单个关键词是否存在于文本中
func contains_keyword(text: String, keyword: String) -> bool:
	"""
	检查文本是否包含指定关键词

	Args:
		text: 预处理后的输入文本
		keyword: 要查找的关键词

	Returns:
		true if keyword found in text
	"""
	if text.is_empty() or keyword.is_empty():
		return false

	var text_words: Dictionary = _build_word_set(text)
	return _word_in_set(keyword, text_words)


## 获取匹配的关键词列表（用于调试）
func get_matching_keywords(
	text: String,
	keywords: Array[String]
) -> Array[String]:
	"""
	返回文本中实际匹配的关键词列表

	Args:
		text: 预处理后的输入文本
		keywords: 要检查的关键词列表

	Returns:
		实际匹配的关键词数组
	"""
	if text.is_empty() or keywords.is_empty():
		return []

	var text_words: Dictionary = _build_word_set(text)
	var matched: Array[String] = []

	for keyword: String in keywords:
		if _word_in_set(keyword, text_words):
			matched.append(keyword)

	return matched


## 私有：将文本转换为词集合（Dictionary 实现 O(1) 查找）
func _build_word_set(text: String) -> Dictionary:
	"""
	将文本拆分为词并构建查找集合

	使用 Dictionary 的 has() 方法实现 O(1) 查找，
	比 Array 的 find() O(n) 更高效
	"""
	var word_set: Dictionary = {}
	var words: PackedStringArray = text.split(" ", false)

	for word: String in words:
		if not word.is_empty():
			word_set[word] = true

	return word_set


## 私有：检查词是否在集合中
func _word_in_set(word: String, word_set: Dictionary) -> bool:
	return word_set.has(word)


## 私有：匹配 required 关键词（AND逻辑）
func _match_required_keywords(
	required_keywords: Array[String],
	text_words: Dictionary
) -> float:
	"""
	计算 required 关键词匹配得分

	Returns:
		1.0 if all required keywords matched, 0.0 otherwise
		If no required keywords, returns BASE_SCORE_NO_REQUIRED
	"""
	if required_keywords.is_empty():
		return BASE_SCORE_NO_REQUIRED

	var matched_count: int = 0
	for keyword: String in required_keywords:
		if _word_in_set(keyword, text_words):
			matched_count += 1

	var ratio: float = float(matched_count) / required_keywords.size()
	# Required 必须全部匹配，否则返回 0
	return 1.0 if ratio >= 1.0 else 0.0


## 私有：计算 optional 关键词加分
func _calculate_optional_bonus(
	optional_keywords: Array[String],
	text_words: Dictionary
) -> float:
	"""
	计算 optional 关键词的加分

	每个匹配的 optional 关键词给予 OPTIONAL_BONUS_PER_WORD 加分，
	但总分不超过 MAX_OPTIONAL_BONUS
	"""
	if optional_keywords.is_empty():
		return 0.0

	var matched_count: int = 0
	for keyword: String in optional_keywords:
		if _word_in_set(keyword, text_words):
			matched_count += 1

	return minf(matched_count * OPTIONAL_BONUS_PER_WORD, MAX_OPTIONAL_BONUS)