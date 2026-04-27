extends Node

# 玩家数据
var player_name: String = ""
var player_age: int = 0
var current_lang: String = "zh"
var current_scene: String = "MainMenu"

# 游戏进度
var unlocked_areas: Array[String] = ["SpiritForest"]
var completed_dialogues: Array[String] = []
var vocabulary_learned: Array[String] = []

# 语言经验值
var lxp_score: int = 0

# 信号
signal language_changed(lang: String)
signal player_info_updated(name: String, age: int)
signal progress_saved()

func _ready() -> void:
	load_progress()

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
		"current_lang": current_lang,
		"unlocked_areas": unlocked_areas,
		"lxp_score": lxp_score,
		"completed_dialogues": completed_dialogues,
		"vocabulary_learned": vocabulary_learned
	}

	var file = FileAccess.open("user://save.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
		progress_saved.emit()

func load_progress() -> bool:
	if FileAccess.file_exists("user://save.json"):
		var file = FileAccess.open("user://save.json", FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var data = JSON.parse_string(json_string)
			if data and data is Dictionary:
				player_name = data.get("player_name", "")
				player_age = data.get("player_age", 0)
				current_lang = data.get("current_lang", "zh")
				# Convert arrays to typed Array[String]
				var areas_data = data.get("unlocked_areas", ["SpiritForest"])
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
	unlocked_areas = ["SpiritForest"]
	completed_dialogues.clear()
	vocabulary_learned.clear()
	save_progress()
