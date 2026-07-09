class_name SceneConfig
extends RefCounted

# Core identification
var scene_id: String = ""
var display_name: String = ""
var chapter: int = 0
var order: int = 0

# Resources
var background_resource: String
var bgm_resource: String
var ambient_resource: String

# NPCs and dialogue
var npcs: Array[NpcSceneConfig] = []
var dialogue_tree_id: String

# Events
var entry_events: Array[Dictionary] = []
var exit_events: Array[Dictionary] = []

# Unlock and revisit
var unlock_condition: Dictionary = {}
var revisit_allowed: bool = true

# Nested class for NPC configuration in scenes
class NpcSceneConfig:
	var npc_id: String = ""
	var is_primary: bool = false
	var initial_position: String = ""

	func _init(p_npc_id: String = "", p_is_primary: bool = false, p_initial_position: String = ""):
		npc_id = p_npc_id
		is_primary = p_is_primary
		initial_position = p_initial_position

	static func from_json(json_data: Dictionary) -> NpcSceneConfig:
		if not json_data.has("npc_id"):
			push_error("NpcSceneConfig.from_json: missing required field 'npc_id'")
			return null

		var config := NpcSceneConfig.new()
		config.npc_id = str(json_data.get("npc_id", ""))
		config.is_primary = SceneConfig._parse_bool(json_data.get("is_primary", false))
		config.initial_position = str(json_data.get("initial_position", ""))

		return config

static func from_json(json_data: Dictionary) -> SceneConfig:
	# Validate required fields
	var required_fields := ["scene_id", "display_name", "chapter", "order"]
	for field in required_fields:
		if not json_data.has(field):
			push_error("SceneConfig.from_json: missing required field '%s'" % field)
			return null

	var config := SceneConfig.new()

	# Core identification
	config.scene_id = str(json_data.get("scene_id", ""))
	config.display_name = str(json_data.get("display_name", ""))

	# Chapter and order with type safety
	var chapter_value = json_data.get("chapter", 0)
	if chapter_value is int:
		config.chapter = chapter_value
	elif chapter_value is float:
		config.chapter = int(chapter_value)
	else:
		push_error("SceneConfig.from_json: 'chapter' must be a number")
		return null

	var order_value = json_data.get("order", 0)
	if order_value is int:
		config.order = order_value
	elif order_value is float:
		config.order = int(order_value)
	else:
		push_error("SceneConfig.from_json: 'order' must be a number")
		return null

	# Resources
	config.background_resource = str(json_data.get("background_resource", ""))
	config.bgm_resource = str(json_data.get("bgm_resource", ""))
	config.ambient_resource = str(json_data.get("ambient_resource", ""))

	# NPCs
	config.npcs = []
	if json_data.has("npcs"):
		var npcs_data = json_data.get("npcs")
		if npcs_data is Array:
			for npc_data in npcs_data:
				if npc_data is Dictionary:
					var npc_config := NpcSceneConfig.from_json(npc_data)
					if npc_config != null:
						config.npcs.append(npc_config)

	# Dialogue
	config.dialogue_tree_id = str(json_data.get("dialogue_tree_id", ""))

	# Events
	config.entry_events = []
	if json_data.has("entry_events"):
		var entry_data = json_data.get("entry_events")
		if entry_data is Array:
			for event in entry_data:
				if event is Dictionary:
					config.entry_events.append(event)

	config.exit_events = []
	if json_data.has("exit_events"):
		var exit_data = json_data.get("exit_events")
		if exit_data is Array:
			for event in exit_data:
				if event is Dictionary:
					config.exit_events.append(event)

	# Unlock and revisit
	if json_data.has("unlock_condition"):
		var unlock_data = json_data.get("unlock_condition")
		if unlock_data is Dictionary:
			config.unlock_condition = unlock_data
		else:
			config.unlock_condition = {}
	else:
		config.unlock_condition = {}

	config.revisit_allowed = _parse_bool(json_data.get("revisit_allowed", true))

	return config


## Parse bool from JSON value (handles string "true"/"yes", numbers, and bools)
static func _parse_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is String:
		return value.to_lower() in ["true", "yes", "1"]
	return false
