## SpiritDatabase.gd
## Foundation layer singleton for word spirit static definitions
## Implements Stories WS-02, WS-03, WS-04
## Loads spirit_database.json at startup, provides O(1) query interfaces
## Architecture: ADR-0010
extends Node

# ── Constants ─────────────────────────────────────────────────────────────

## Overridable path for testing — do NOT override in production
var DATABASE_PATH: String = "res://assets/data/spirits/spirit_database.json"

# Rarity score multipliers (downstream systems read these)
const RARITY_MULTIPLIER_COMMON: float = 1.0
const RARITY_MULTIPLIER_RARE: float = 2.0
const RARITY_MULTIPLIER_LEGENDARY: float = 5.0

# ── State Machine ────────────────────────────────────────────────────────

enum State {
	UNLOADED,
	LOADING,
	LOADED,
	ERROR
}

var current_state: State = State.UNLOADED

# ── Internal Data ─────────────────────────────────────────────────────────

var _spirits: Array[Dictionary] = []
var _id_index_map: Dictionary = {}  # spirit_id → array index (O(1) lookup)
var _npc_spirit_map: Dictionary = {}  # npc_id → array of spirit_ids

# ── Signals ───────────────────────────────────────────────────────────────

signal database_loaded(count: int)
signal database_load_error(error_message: String)

# ── Lifecycle ─────────────────────────────────────────────────────────────

## Called at game startup — loads and indexes the spirit database
func initialize() -> void:
	current_state = State.LOADING

	if not FileAccess.file_exists(DATABASE_PATH):
		push_warning("Spirit database file missing: %s" % DATABASE_PATH)
		current_state = State.ERROR
		database_load_error.emit("Database file missing: %s" % DATABASE_PATH)
		_init_empty()
		return

	var json_string: String = FileAccess.get_file_as_string(DATABASE_PATH)
	if json_string.is_empty() and FileAccess.get_open_error() != OK:
		push_warning("Failed to read spirit database: %s" % error_string(FileAccess.get_open_error()))
		current_state = State.ERROR
		database_load_error.emit("Failed to read file")
		_init_empty()
		return

	var parse_result = JSON.parse_string(json_string)
	if parse_result == null:
		push_warning("Spirit database JSON parse failed")
		current_state = State.ERROR
		database_load_error.emit("JSON parse error")
		_init_empty()
		return

	if not parse_result is Array:
		push_warning("Spirit database JSON root must be an array, got: %s" % typeof(parse_result))
		current_state = State.ERROR
		database_load_error.emit("JSON root is not an array")
		_init_empty()
		return

	_build_index(parse_result as Array)

	current_state = State.LOADED
	database_loaded.emit(_spirits.size())


## Called on game shutdown or database reload
func shutdown() -> void:
	_spirits.clear()
	_id_index_map.clear()
	_npc_spirit_map.clear()
	current_state = State.UNLOADED

# ── Query Interface: Spirit Lookup ────────────────────────────────────────

## Get a single spirit by ID. Returns null if not found.
func get_spirit(spirit_id: String) -> Dictionary:
	if current_state != State.LOADED:
		return {}

	if not _id_index_map.has(spirit_id):
		return {}

	var index: int = _id_index_map[spirit_id]
	return _spirits[index].duplicate(true)


## Get all spirits. Returns empty array if not loaded.
func get_all_spirits() -> Array[Dictionary]:
	if current_state != State.LOADED:
		return []

	var result: Array[Dictionary] = []
	for spirit in _spirits:
		result.append(spirit.duplicate(true))
	return result


## Get spirits by category. Returns empty array if category not found.
func get_spirits_by_category(category: String) -> Array[Dictionary]:
	if current_state != State.LOADED:
		return []

	var result: Array[Dictionary] = []
	for spirit in _spirits:
		if spirit.get("category", "") == category:
			result.append(spirit.duplicate(true))
	return result


## Get spirits by rarity. Returns empty array if rarity not found.
func get_spirits_by_rarity(rarity: String) -> Array[Dictionary]:
	if current_state != State.LOADED:
		return []

	var result: Array[Dictionary] = []
	for spirit in _spirits:
		if spirit.get("rarity", "") == rarity:
			result.append(spirit.duplicate(true))
	return result


## Get spirit rarity string ("common" / "rare" / "legendary"). Returns null if not found.
func get_spirit_rarity(spirit_id: String) -> Variant:
	if current_state != State.LOADED:
		return null

	if not _id_index_map.has(spirit_id):
		return null

	var index: int = _id_index_map[spirit_id]
	return _spirits[index].get("rarity", null)


## Get the rarity score multiplier for a spirit. Returns 1.0 if not found.
func get_rarity_multiplier(spirit_id: String) -> float:
	var rarity = get_spirit_rarity(spirit_id)
	match rarity:
		"rare":
			return RARITY_MULTIPLIER_RARE
		"legendary":
			return RARITY_MULTIPLIER_LEGENDARY
		_:
			return RARITY_MULTIPLIER_COMMON  # default to common

# ── Query Interface: NPC Association ──────────────────────────────────────

## Get all spirits associated with an NPC. Returns empty array if NPC has no spirits.
func get_spirits_by_npc(npc_id: String) -> Array[Dictionary]:
	if current_state != State.LOADED:
		return []

	var spirit_ids: Array = _npc_spirit_map.get(npc_id, [])
	var result: Array[Dictionary] = []
	for sid in spirit_ids:
		var spirit = get_spirit(sid)
		if not spirit.is_empty():
			result.append(spirit)
	return result


## Get the NPC ID associated with a spirit. Returns null if no association.
func get_associated_npc(spirit_id: String) -> Variant:
	var spirit = get_spirit(spirit_id)
	if spirit.is_empty():
		return null

	return spirit.get("associated_npc_id", null)

# ── Internal Helpers ──────────────────────────────────────────────────────

func _init_empty() -> void:
	_spirits.clear()
	_id_index_map.clear()
	_npc_spirit_map.clear()


func _build_index(data: Array) -> void:
	_spirits.clear()
	_id_index_map.clear()
	_npc_spirit_map.clear()

	for i in range(data.size()):
		var entry: Dictionary = data[i] as Dictionary

		# Validate required field: id
		var spirit_id: String = entry.get("id", "")
		if spirit_id.is_empty():
			push_warning("Spirit entry at index %d has empty id, skipping" % i)
			continue

		# Handle duplicate IDs: later definition overrides earlier
		if _id_index_map.has(spirit_id):
			push_warning("Duplicate spirit_id: %s — later definition overrides" % spirit_id)
			# Remove old entry before appending new one
			var old_index: int = _id_index_map[spirit_id]
			_spirits.remove_at(old_index)
			# Rebuild index map for all entries after old_index
			for idx in range(old_index, _spirits.size()):
				var existing_id: String = _spirits[idx].get("id", "")
				if not existing_id.is_empty():
					_id_index_map[existing_id] = idx

		# Handle empty name: use ID as fallback
		var name_field = entry.get("name", "")
		if name_field is String and (name_field as String).is_empty():
			push_warning("Spirit '%s' has empty name, using ID as fallback" % spirit_id)
			entry["name"] = {"zh_CN": spirit_id, "en": spirit_id}
		elif name_field is Dictionary and name_field.is_empty():
			push_warning("Spirit '%s' has empty name dict, using ID as fallback" % spirit_id)
			entry["name"] = {"zh_CN": spirit_id, "en": spirit_id}

		# Handle empty vocab_words
		var vocab_words = entry.get("vocab_words", [])
		if vocab_words is Array and vocab_words.is_empty():
			push_warning("Spirit '%s' has empty vocab_words — cannot be triggered by dialogue" % spirit_id)

		# Build index
		_spirits.append(entry)
		_id_index_map[spirit_id] = _spirits.size() - 1

		# Build NPC association map
		var npc_id = entry.get("associated_npc_id", null)
		if npc_id != null and not (npc_id is String and (npc_id as String).is_empty()):
			if not _npc_spirit_map.has(npc_id):
				_npc_spirit_map[npc_id] = []
			_npc_spirit_map[npc_id].append(spirit_id)