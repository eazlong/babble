class_name LessonResponseMatcher
extends RefCounted

## Data-driven keyword response matcher for voice lesson scenes.
## Implements the "West Market Lesson 01" clear/understandable/needs-help
## tiers from the scene design without binding the logic to a specific UI.

const RESULT_CLEAR: String = "clear"
const RESULT_UNDERSTANDABLE: String = "understandable"
const RESULT_NEEDS_HELP: String = "needs_help"

static func evaluate(text: String, rule: Dictionary) -> Dictionary:
	var normalized: String = normalize_text(text)
	var clear_phrases: Array[String] = _string_array(rule.get("clear_phrases", []))
	var acceptable_phrases: Array[String] = _string_array(rule.get("acceptable_phrases", []))
	var required_keywords: Array[String] = _string_array(rule.get("required_keywords", []))
	var optional_keywords: Array[String] = _string_array(rule.get("optional_keywords", []))
	var confused_keywords: Array[String] = _string_array(rule.get("confused_keywords", []))

	if normalized.is_empty():
		return _result(RESULT_NEEDS_HELP, [], "empty")

	if _matches_any_phrase(normalized, clear_phrases):
		return _result(RESULT_CLEAR, _matched_keywords(normalized, required_keywords + optional_keywords), "")

	if _matches_any_phrase(normalized, acceptable_phrases):
		return _result(RESULT_UNDERSTANDABLE, _matched_keywords(normalized, required_keywords + optional_keywords), "")

	var matched_required: Array[String] = _matched_keywords(normalized, required_keywords)
	var matched_optional: Array[String] = _matched_keywords(normalized, optional_keywords)
	var matched_confused: Array[String] = _matched_keywords(normalized, confused_keywords)

	if required_keywords.size() > 0 and matched_required.size() == required_keywords.size():
		return _result(RESULT_UNDERSTANDABLE, matched_required + matched_optional, "")

	if required_keywords.is_empty() and matched_optional.size() > 0:
		return _result(RESULT_UNDERSTANDABLE, matched_optional, "")

	if matched_confused.size() > 0:
		return _result(RESULT_NEEDS_HELP, matched_confused, "confused_keyword")

	return _result(RESULT_NEEDS_HELP, matched_required + matched_optional, "missing_keyword")

static func normalize_text(text: String) -> String:
	var lower: String = text.to_lower().strip_edges()
	var result: String = ""
	for i in range(lower.length()):
		var ch: String = lower[i]
		if ch.is_valid_identifier() or ch.is_valid_int() or ch == " " or _is_cjk(ch):
			result += ch
		else:
			result += " "
	while result.contains("  "):
		result = result.replace("  ", " ")
	return result.strip_edges()

static func _matches_any_phrase(text: String, phrases: Array[String]) -> bool:
	for phrase in phrases:
		var normalized_phrase: String = normalize_text(phrase)
		if not normalized_phrase.is_empty() and text.contains(normalized_phrase):
			return true
	return false

static func _matched_keywords(text: String, keywords: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for keyword in keywords:
		var normalized_keyword: String = normalize_text(keyword)
		if not normalized_keyword.is_empty() and text.contains(normalized_keyword):
			result.append(keyword)
	return result

static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in value:
		result.append(str(item))
	return result

static func _result(tier: String, matched: Array[String], reason: String) -> Dictionary:
	return {
		"tier": tier,
		"matched": matched,
		"reason": reason,
	}

static func _is_cjk(ch: String) -> bool:
	if ch.is_empty():
		return false
	var code: int = ch.unicode_at(0)
	return code >= 0x4E00 and code <= 0x9FFF
