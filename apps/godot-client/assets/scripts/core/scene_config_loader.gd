class_name SceneConfigLoader
extends RefCounted

# Signals
signal configs_loaded(count: int)
signal config_load_failed(scene_file: String, error: String)

# Private registry: scene_id -> SceneConfig
var _registry: Dictionary[String, SceneConfig] = {}

func load_scene_configs(config_dir: String = "res://scenes/") -> bool:
	_registry.clear()
	var loaded_count := 0
	var has_errors := false

	var dir: DirAccess = DirAccess.open(config_dir)
	if dir == null:
		push_error("SceneConfigLoader: Failed to open %s directory" % config_dir)
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var file_path := config_dir + file_name
			var result := _load_single_config(file_path)
			if result:
				loaded_count += 1
			else:
				has_errors = true
		file_name = dir.get_next()

	dir.list_dir_end()

	configs_loaded.emit(loaded_count)
	return loaded_count > 0

func _load_single_config(file_path: String) -> bool:
	if not FileAccess.file_exists(file_path):
		push_error("SceneConfigLoader: File does not exist: %s" % file_path)
		config_load_failed.emit(file_path, "File does not exist")
		return false

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var error_msg := "Failed to open file: %s (Error: %d)" % [file_path, FileAccess.get_open_error()]
		push_error("SceneConfigLoader: " + error_msg)
		config_load_failed.emit(file_path, error_msg)
		return false

	var content := file.get_as_text()
	file.close()

	var json_data: Variant = JSON.parse_string(content)
	if json_data == null:
		var error_msg := "Invalid JSON format"
		push_error("SceneConfigLoader: %s in %s" % [error_msg, file_path])
		config_load_failed.emit(file_path, error_msg)
		return false

	if not json_data is Dictionary:
		var error_msg := "Root JSON must be an object"
		push_error("SceneConfigLoader: %s in %s" % [error_msg, file_path])
		config_load_failed.emit(file_path, error_msg)
		return false

	var config: SceneConfig = SceneConfig.from_json(json_data)
	if config == null:
		var error_msg := "Failed to parse SceneConfig"
		push_error("SceneConfigLoader: %s in %s" % [error_msg, file_path])
		config_load_failed.emit(file_path, error_msg)
		return false

	# Check for duplicate scene_id
	if _registry.has(config.scene_id):
		push_warning("SceneConfigLoader: Duplicate scene_id '%s' in %s, overwriting previous definition" % [config.scene_id, file_path])

	_registry[config.scene_id] = config
	return true

func get_scene_config(scene_id: String) -> SceneConfig:
	if _registry.has(scene_id):
		return _registry[scene_id]
	return null

func get_all_scene_configs() -> Dictionary[String, SceneConfig]:
	return _registry.duplicate()

func has_scene_config(scene_id: String) -> bool:
	return _registry.has(scene_id)
