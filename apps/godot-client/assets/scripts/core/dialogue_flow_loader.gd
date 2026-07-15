class_name DialogueFlowLoader
extends RefCounted

const DEFAULT_CONFIG_DIR: String = "res://assets/resources/dialogue_flows/"
const FALLBACK_LANGUAGE: String = "en"

var _flows: Dictionary[String, Dictionary] = {}
var _line_index: Dictionary[String, Dictionary] = {}
var _errors: Array[String] = []

func load_dialogue_flows(config_dir: String = DEFAULT_CONFIG_DIR) -> bool:
	clear()
	var dir: DirAccess = DirAccess.open(config_dir)
	if dir == null:
		_record_error("Failed to open dialogue flow directory: %s" % config_dir)
		return false

	var loaded_count: int = 0
	var has_file_errors: bool = false
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var file_path: String = config_dir.path_join(file_name)
			if _load_single_file(file_path):
				loaded_count += 1
			else:
				has_file_errors = true
		file_name = dir.get_next()
	dir.list_dir_end()

	return loaded_count > 0 and not has_file_errors

func clear() -> void:
	_flows.clear()
	_line_index.clear()
	_errors.clear()

func get_errors() -> Array[String]:
	return _errors.duplicate()

func has_flow(flow_id: String) -> bool:
	return _flows.has(flow_id)

func get_flow(flow_id: String) -> Dictionary:
	if not _flows.has(flow_id):
		push_warning("[DialogueFlowLoader] Unknown flow_id: %s" % flow_id)
		return {}
	return _flows[flow_id].duplicate(true)

func get_lines(flow_id: String, lang: String, params: Dictionary = {}) -> Array[Dictionary]:
	if not _flows.has(flow_id):
		push_warning("[DialogueFlowLoader] Unknown flow_id: %s" % flow_id)
		return []

	var flow: Dictionary = _flows[flow_id]
	var flow_speaker: String = str(flow.get("speaker", ""))
	var flow_voice: String = str(flow.get("voice", ""))
	var result: Array[Dictionary] = []
	var lines: Array = flow.get("lines", [])
	for line_value in lines:
		if not line_value is Dictionary:
			continue
		var line: Dictionary = line_value
		var line_key: String = str(line.get("key", ""))
		var text_map: Dictionary = line.get("text", {})
		var localized_text: String = _localize_text(flow_id, line_key, text_map, lang)
		result.append({
			"key": line_key,
			"speaker": str(line.get("speaker", flow_speaker)),
			"voice": str(line.get("voice", flow_voice)),
			"text": _apply_placeholders(localized_text, params),
		})
	return result

func get_text_by_key(key: String, lang: String, params: Dictionary = {}) -> String:
	if not _line_index.has(key):
		push_warning("[DialogueFlowLoader] Unknown dialogue key: %s" % key)
		return ""
	var indexed: Dictionary = _line_index[key]
	var flow_id: String = str(indexed.get("flow_id", ""))
	var line: Dictionary = indexed.get("line", {})
	var text_map: Dictionary = line.get("text", {})
	return _apply_placeholders(_localize_text(flow_id, key, text_map, lang), params)

func _load_single_file(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		_record_error("Dialogue flow file does not exist: %s" % file_path)
		return false

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		_record_error("Failed to open dialogue flow file: %s" % file_path)
		return false

	var content: String = file.get_as_text()
	file.close()
	var json_data: Variant = JSON.parse_string(content)
	if json_data == null or not json_data is Dictionary:
		_record_error("Dialogue flow file root must be a JSON object: %s" % file_path)
		return false

	var root: Dictionary = json_data
	if not root.has("flows") or not root["flows"] is Array:
		_record_error("Dialogue flow file missing flows array: %s" % file_path)
		return false

	var has_file_error: bool = false
	for flow_value in root["flows"]:
		if not flow_value is Dictionary:
			_record_error("Skipping non-object flow in %s" % file_path)
			continue
		var flow: Dictionary = flow_value
		var is_duplicate: bool = _is_duplicate_flow(flow)
		if not _register_flow(flow, file_path) and is_duplicate:
			has_file_error = true
	return not has_file_error

func _register_flow(flow: Dictionary, file_path: String) -> bool:
	var flow_id: String = str(flow.get("flow_id", ""))
	if flow_id.is_empty():
		_record_error("Skipping flow with missing flow_id in %s" % file_path)
		return false
	if _flows.has(flow_id):
		_record_error("Duplicate flow_id rejected: %s in %s" % [flow_id, file_path])
		return false
	if not flow.has("lines") or not flow["lines"] is Array:
		_record_error("Skipping flow with missing lines array: %s" % flow_id)
		return false

	var valid_lines: Array[Dictionary] = []
	var lines: Array = flow["lines"]
	var flow_ok: bool = true
	for line_value in lines:
		if not line_value is Dictionary:
			_record_error("Skipping non-object line in flow: %s" % flow_id)
			flow_ok = false
			continue
		var line: Dictionary = line_value
		if not line.has("text") or not line["text"] is Dictionary:
			_record_error("Skipping line with invalid text in flow: %s" % flow_id)
			flow_ok = false
			continue
		valid_lines.append(line)

	var normalized_flow: Dictionary = flow.duplicate(true)
	normalized_flow["lines"] = valid_lines
	_flows[flow_id] = normalized_flow
	for line in valid_lines:
		var key: String = str(line.get("key", ""))
		if not key.is_empty() and not _line_index.has(key):
			_line_index[key] = {
				"flow_id": flow_id,
				"line": line,
			}
	return flow_ok

func _is_duplicate_flow(flow: Dictionary) -> bool:
	var flow_id: String = str(flow.get("flow_id", ""))
	return not flow_id.is_empty() and _flows.has(flow_id)

func _localize_text(flow_id: String, line_key: String, text_map: Dictionary, lang: String) -> String:
	if text_map.has(lang):
		return str(text_map[lang])
	if text_map.has(FALLBACK_LANGUAGE):
		push_warning("[DialogueFlowLoader] Missing '%s' for %s/%s, using '%s'" % [lang, flow_id, line_key, FALLBACK_LANGUAGE])
		return str(text_map[FALLBACK_LANGUAGE])
	for fallback_key in text_map.keys():
		push_warning("[DialogueFlowLoader] Missing '%s' and '%s' for %s/%s, using '%s'" % [lang, FALLBACK_LANGUAGE, flow_id, line_key, str(fallback_key)])
		return str(text_map[fallback_key])
	push_warning("[DialogueFlowLoader] Empty text map for %s/%s" % [flow_id, line_key])
	return ""

func _apply_placeholders(text: String, params: Dictionary) -> String:
	var result: String = text
	for placeholder in _find_placeholders(text):
		var name: String = placeholder.substr(1, placeholder.length() - 2)
		if params.has(name):
			result = result.replace(placeholder, str(params[name]))
		else:
			push_warning("[DialogueFlowLoader] Missing placeholder param: %s" % name)
	return result

func _find_placeholders(text: String) -> Array[String]:
	var placeholders: Array[String] = []
	var regex := RegEx.new()
	var compile_result: Error = regex.compile("\\{[A-Za-z_][A-Za-z0-9_]*\\}")
	if compile_result != OK:
		return placeholders
	for result in regex.search_all(text):
		var token: String = result.get_string()
		if not placeholders.has(token):
			placeholders.append(token)
	return placeholders

func _record_error(message: String) -> void:
	_errors.append(message)
	push_warning("[DialogueFlowLoader] %s" % message)
