extends Node

# 全局课程语言配置
# 默认是中国人学英语；交换这两组配置即可改成美国人学中文等反向课程。
const SOURCE_LANGUAGE_CODE: String = "zh"
const SOURCE_LANGUAGE_NAME: String = "中文"
const SPECIAL_LANGUAGE_CODE: String = "en"
const SPECIAL_LANGUAGE_NAME: String = "英语"
const DEFAULT_SPECIAL_LANGUAGE_PLAYER_NAME: String = "Carl"

# 玩家数据
var player_name: String = ""
var player_age: int = 0
var player_cefr_level: String = "A1"  # A1, A2, B1, B2 — used by coach service
var current_lang: String = SOURCE_LANGUAGE_CODE
var current_scene: String = "MainMenu"

# 游戏进度
var unlocked_areas: Array[String] = ["BeginningFP"]
var completed_dialogues: Array[String] = []
var vocabulary_learned: Array[String] = []

# 词灵系统
var unlocked_spirits: Array[String] = []
var spirit_usage_counts: Dictionary[String, int] = {}

# 语言经验值
var lxp_score: int = 0

# 信号
signal language_changed(lang: String)
signal player_info_updated(name: String, age: int)
signal progress_saved()
signal spirit_unlock_dismissed()

func _ready() -> void:
	# Connect to SaveSystem autoload singleton for async data restoration
	var save_system = get_node("/root/SaveSystem")
	save_system.load_completed.connect(_on_save_loaded)
	load_progress()

func _on_save_loaded(slot_id: int, data: Dictionary) -> void:
	"""Restore spirit data after SaveSystem async load completes"""
	var spirit_data = data.get("unlocked_spirits", [])
	unlocked_spirits.clear()
	for sid in spirit_data:
		unlocked_spirits.append(sid)

	var usage_data = data.get("spirit_usage_counts", {})
	spirit_usage_counts.clear()
	for sid in usage_data.keys():
		spirit_usage_counts[sid] = usage_data[sid]

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

func save_progress() -> void:
	var save_data = {
		"player_name": player_name,
		"player_age": player_age,
		"player_cefr_level": player_cefr_level,
		"current_lang": current_lang,
		"unlocked_areas": unlocked_areas,
		"lxp_score": lxp_score,
		"completed_dialogues": completed_dialogues,
		"vocabulary_learned": vocabulary_learned,
		"unlocked_spirits": unlocked_spirits,
		"spirit_usage_counts": spirit_usage_counts
	}
	var save_system = get_node("/root/SaveSystem")
	save_system.save(1, save_data)

func load_progress() -> bool:
	# Note: SaveSystem.load() is async and emits load_completed signal
	# For synchronous loading in _ready(), we'll keep a fallback for now
	if FileAccess.file_exists("user://save.json"):
		var file = FileAccess.open("user://save.json", FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var data = JSON.parse_string(json_string)
			if data and data is Dictionary:
				player_name = data.get("player_name", "")
				player_age = data.get("player_age", 0)
				player_cefr_level = data.get("player_cefr_level", "A1")
				current_lang = data.get("current_lang", SOURCE_LANGUAGE_CODE)
				# Convert arrays to typed Array[String]
				var areas_data = data.get("unlocked_areas", ["BeginningFP"])
				unlocked_areas.clear()
				for area in areas_data:
					unlocked_areas.append(area)
				lxp_score = data.get("lxp_score", 0)
				var dialogues_data = data.get("completed_dialogues", [])
				completed_dialogues.clear()
				for dialogue in dialogues_data:
					completed_dialogues.append(dialogue)
				var vocab_data = data.get("vocabulary_learned", [])
				vocabulary_learned.clear()
				for vocab in vocab_data:
					vocabulary_learned.append(vocab)
				return true
	return false

func reset() -> void:
	player_name = ""
	player_age = 0
	lxp_score = 0
	unlocked_areas = ["BeginningFP"]
	completed_dialogues.clear()
	vocabulary_learned.clear()
	unlocked_spirits.clear()
	spirit_usage_counts.clear()
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
