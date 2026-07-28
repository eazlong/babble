extends Node

# 全局课程语言配置
# 默认是中国人学英语；交换这两组配置即可改成美国人学中文等反向课程。
const SOURCE_LANGUAGE_CODE: String = "zh"
const SOURCE_LANGUAGE_NAME: String = "中文"
const SPECIAL_LANGUAGE_CODE: String = "en"
const SPECIAL_LANGUAGE_NAME: String = "英语"
const DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME: String = "Carl"
const DEFAULT_SAVE_SLOT: int = 1
const TEST_MODE_SKIP_AUTO_LOAD_SETTING: String = "game/test_mode_skip_auto_load_save"
const SCENE_PATHS: Dictionary = {
	"MainMenu": "res://assets/scenes/MainMenu.tscn",
	"BeginningFP": "res://assets/scenes/BeginningFP.tscn",
	"beginning": "res://assets/scenes/BeginningFP.tscn",
	"MirageInnIntroduction": "res://assets/scenes/MirageInnIntroduction.tscn",
	"ChangAnMarket": "res://assets/scenes/ChangAnMarket.tscn",
	"SpellLibrary": "res://assets/scenes/SpellLibrary.tscn",
	"spell_library": "res://assets/scenes/SpellLibrary.tscn",
	"RainbowGarden": "res://assets/scenes/RainbowGarden.tscn",
	"rainbow_garden": "res://assets/scenes/RainbowGarden.tscn",
	"WordSpiritLibraryArchiveHall": "res://assets/scenes/WordSpiritLibraryArchiveHall.tscn",
	"word_spirit_library_archive_hall": "res://assets/scenes/WordSpiritLibraryArchiveHall.tscn",
}

# 玩家数据
var player_name: String = ""
var player_age: int = 0
var player_cefr_level: String = "A1"  # A1, A2, B1, B2 — used by coach service
var current_lang: String = SOURCE_LANGUAGE_CODE
var current_scene: String = "MainMenu"
var save_loaded: bool = false

# 游戏进度
var unlocked_areas: Array[String] = ["BeginningFP"]
var completed_dialogues: Array[String] = []
var vocabulary_learned: Array[String] = []

# 词灵系统
var unlocked_spirits: Array[String] = []
var spirit_usage_counts: Dictionary[String, int] = {}

# 语言经验值
var lxp_score: int = 0

# 归卷厅持久化进度（阻塞 5：词灵归卷厅场景所需最小字段）
var archive_hall_progress: Dictionary = {}
var ink_shadow_queue: Array[String] = []

# 信号
signal language_changed(lang: String)
signal player_info_updated(name: String, age: int)
signal progress_saved()
signal spirit_unlock_dismissed()

func _ready() -> void:
	# Connect to SaveSystem autoload singleton for async data restoration
	var save_system = get_node("/root/SaveSystem")
	save_system.load_completed.connect(_on_save_loaded)
	if _should_skip_auto_load_save():
		print("[GameManager] Test mode enabled: skipping auto save load.")
		return
	load_progress()

func _should_skip_auto_load_save() -> bool:
	return bool(ProjectSettings.get_setting(TEST_MODE_SKIP_AUTO_LOAD_SETTING, false))

func is_test_mode_skip_auto_load_save() -> bool:
	return _should_skip_auto_load_save()

func _on_save_loaded(slot_id: int, data: Dictionary) -> void:
	"""Restore save data after SaveSystem async load completes."""
	if slot_id != DEFAULT_SAVE_SLOT:
		return
	_restore_from_save_data(data)

func _restore_from_save_data(data: Dictionary) -> void:
	player_name = str(data.get("player_name", player_name))
	player_age = int(data.get("player_age", player_age))
	player_cefr_level = str(data.get("player_cefr_level", player_cefr_level))
	current_lang = str(data.get("current_lang", current_lang))
	current_scene = str(data.get("current_scene_id", data.get("current_scene", current_scene)))
	lxp_score = int(data.get("lxp_score", lxp_score))

	# 归卷厅进度恢复
	archive_hall_progress = data.get("archive_hall_progress", {}).duplicate(true) if data.get("archive_hall_progress", {}) is Dictionary else {}
	var ink_data: Array = data.get("ink_shadow_queue", [])
	ink_shadow_queue.clear()
	for word in ink_data:
		var word_str := str(word)
		if not ink_shadow_queue.has(word_str):
			ink_shadow_queue.append(word_str)

	var areas_data: Array = data.get("unlocked_areas", data.get("unlocked_scenes", ["BeginningFP"]))
	unlocked_areas.clear()
	for area in areas_data:
		var area_id := str(area)
		if not unlocked_areas.has(area_id):
			unlocked_areas.append(area_id)
	if unlocked_areas.is_empty():
		unlocked_areas.append("BeginningFP")

	var dialogues_data: Array = data.get("completed_dialogues", data.get("completed_scenes", []))
	completed_dialogues.clear()
	for dialogue in dialogues_data:
		var dialogue_id := str(dialogue)
		if not completed_dialogues.has(dialogue_id):
			completed_dialogues.append(dialogue_id)

	var vocab_data: Array = data.get("vocabulary_learned", [])
	vocabulary_learned.clear()
	for vocab in vocab_data:
		var vocab_id := str(vocab)
		if not vocabulary_learned.has(vocab_id):
			vocabulary_learned.append(vocab_id)

	var spirit_data = data.get("unlocked_spirits", [])
	unlocked_spirits.clear()
	for sid in spirit_data:
		var spirit_id := str(sid)
		if not unlocked_spirits.has(spirit_id):
			unlocked_spirits.append(spirit_id)

	var usage_data = data.get("spirit_usage_counts", {})
	spirit_usage_counts.clear()
	for sid in usage_data.keys():
		spirit_usage_counts[str(sid)] = int(usage_data[sid])

	if has_node("/root/MagicEchoManager"):
		var magic_echo_manager = get_node("/root/MagicEchoManager")
		if magic_echo_manager.has_method("import_state"):
			magic_echo_manager.call("import_state", data.get("magic_echo", {}))
		if magic_echo_manager.has_method("reconcile_local_recordings"):
			magic_echo_manager.call("reconcile_local_recordings")

	save_loaded = true

	# Notify SpiritCollectionManager (if initialized)
	if has_node("/root/SpiritCollectionManager"):
		var spirit_mgr = get_node("/root/SpiritCollectionManager")
		if spirit_mgr.has_method("restore_from_save"):
			spirit_mgr.call("restore_from_save", {
				"unlocked_spirits": unlocked_spirits,
				"spirit_usage_counts": spirit_usage_counts
			})

func set_player_info(name: String, age: int) -> void:
	player_name = name
	player_age = age
	player_info_updated.emit(name, age)
	save_progress()

func set_language(lang: String) -> void:
	current_lang = lang
	language_changed.emit(lang)
	save_progress()

func set_checkpoint(scene_id: String, save_now: bool = true) -> void:
	current_scene = scene_id
	if not unlocked_areas.has(scene_id):
		unlocked_areas.append(scene_id)
	if save_now:
		save_progress()

func save_progress() -> void:
	var save_data = {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",
		"play_time_seconds": 0,
		"current_scene_id": current_scene,
		"current_scene": current_scene,
		"unlocked_scenes": unlocked_areas,
		"completed_scenes": completed_dialogues,
		"npc_states": {},
		"has_completed_tutorial": completed_dialogues.has("beginning_prologue_complete"),
		"tutorial_step": 5 if completed_dialogues.has("beginning_prologue_complete") else 0,
		"current_dialogue_node": null,
		"active_dialogue_tree_id": null,
		"input_permission_state": {
			"has_mic_permission": AudioServer.get_bus_index("Record") != -1,
		},
		"settings_overrides": {},
		"player_name": player_name,
		"player_age": player_age,
		"player_cefr_level": player_cefr_level,
		"current_lang": current_lang,
		"unlocked_areas": unlocked_areas,
		"lxp_score": lxp_score,
		"archive_hall_progress": archive_hall_progress,
		"ink_shadow_queue": ink_shadow_queue,
		"completed_dialogues": completed_dialogues,
		"vocabulary_learned": vocabulary_learned,
		"unlocked_spirits": unlocked_spirits,
		"spirit_usage_counts": spirit_usage_counts,
		"magic_echo": _magic_echo_save_data()
	}
	var save_system = get_node("/root/SaveSystem")
	save_system.save(DEFAULT_SAVE_SLOT, save_data)

func _magic_echo_save_data() -> Dictionary:
	var magic_echo_manager: Node = get_node_or_null("/root/MagicEchoManager")
	if magic_echo_manager == null or not magic_echo_manager.has_method("export_state"):
		return {}
	var state: Variant = magic_echo_manager.call("export_state")
	if state is Dictionary:
		return state.duplicate(true)
	return {}

func load_progress() -> bool:
	var save_system = get_node("/root/SaveSystem")
	var slot_path: String = save_system.get_save_path(DEFAULT_SAVE_SLOT)
	if FileAccess.file_exists(slot_path):
		var slot_file := FileAccess.open(slot_path, FileAccess.READ)
		if slot_file:
			var slot_json := slot_file.get_as_text()
			slot_file.close()
			var slot_data = JSON.parse_string(slot_json)
			if slot_data is Dictionary:
				_restore_from_save_data(slot_data)
				return true

	# Legacy fallback for old development saves.
	if FileAccess.file_exists("user://save.json"):
		var file = FileAccess.open("user://save.json", FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var data = JSON.parse_string(json_string)
			if data and data is Dictionary:
				_restore_from_save_data(data)
				return true
	return false

func get_scene_path(scene_id: String = "") -> String:
	var resolved_id: String = current_scene if scene_id.is_empty() else scene_id
	return str(SCENE_PATHS.get(resolved_id, ""))

func should_resume_to_scene(boot_scene_id: String) -> bool:
	return save_loaded and current_scene != "" and current_scene != boot_scene_id and get_scene_path(current_scene) != ""

## 归卷厅进度访问器（阻塞 5：场景只读 autoload 状态，不直接改字段）
func set_archive_hall_progress(progress: Dictionary) -> void:
	archive_hall_progress = progress.duplicate(true)

func get_archive_hall_progress() -> Dictionary:
	return archive_hall_progress.duplicate(true)

func set_ink_shadow_queue(queue: Array[String]) -> void:
	ink_shadow_queue = queue.duplicate()

func get_ink_shadow_queue() -> Array[String]:
	return ink_shadow_queue.duplicate()

func reset() -> void:
	player_name = ""
	player_age = 0
	lxp_score = 0
	unlocked_areas = ["BeginningFP"]
	completed_dialogues.clear()
	vocabulary_learned.clear()
	unlocked_spirits.clear()
	spirit_usage_counts.clear()
	archive_hall_progress.clear()
	ink_shadow_queue.clear()
	save_progress()

func show_spirit_unlock(spirit_id: String) -> void:
	"""Display spirit unlock overlay."""
	var overlay = SpiritUnlockOverlay.new()
	get_tree().root.add_child(overlay)
	overlay.display_spirit_unlock(spirit_id)
	overlay.dismissed.connect(_on_spirit_overlay_dismissed)

func _on_spirit_overlay_dismissed() -> void:
	"""Spirit unlock animation finished - resume dialogue."""
	spirit_unlock_dismissed.emit()

	# Resume DialogueManager if waiting
	if has_node("/root/DialogueManager"):
		var dialogue_mgr = get_node("/root/DialogueManager")
		if dialogue_mgr.has_method("resume_after_spirit_unlock"):
			dialogue_mgr.call("resume_after_spirit_unlock")
