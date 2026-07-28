## save_system.gd
## Save System — Core layer singleton
## Stories: S-01 (Structure/Init), S-02 (Save Flow), S-03 (Load Flow), S-10 (Signals)
## Manages save slot lifecycle, data structure, directory init, slot status query,
## atomic async save/load flow with MD5 checksum.
## Out of scope: delete (S-06), load checksum validation edge cases (S-05)
class_name SaveSystemClass
extends Node

# ── Signals ─────────────────────────────────────────────────────────────────

## Emitted when a save operation completes successfully.
signal save_completed(slot_id: int)

## Emitted when a save operation fails.
signal save_failed(slot_id: int, error_message: String)

## Emitted when a load operation completes successfully.
## LinguaQuest adaptation: includes loaded data for GameManager to restore state.
signal load_completed(slot_id: int, data: Dictionary)

## Emitted when a load operation fails.
signal load_failed(slot_id: int, error_message: String)

## Emitted when a save deletion completes successfully.
signal save_deleted(slot_id: int)

## Emitted when a save deletion fails.
signal save_delete_failed(slot_id: int, error_message: String)

# ── Constants ───────────────────────────────────────────────────────────────

const MAX_SAVE_SLOTS: int = 3
const SAVE_DIR: String = "user://saves/"

# ── Enums ─────────────────────────────────────────────────────────────────

enum State {
	IDLE,
	SAVING,
	LOADING,
	DELETING,
	ERROR,
}

enum SlotStatus {
	EMPTY,
	OCCUPIED,
	INVALID,
}

# ── State ─────────────────────────────────────────────────────────────────

var current_state: State = State.IDLE

# Internal save directory (overridable for testing)
var _save_dir: String = SAVE_DIR

## Test-only hook: override the save directory path.
## Must be set BEFORE initialize() is called.
var _test_save_dir: String = "":
	set(value):
		_save_dir = value
	get:
		return _save_dir


# Async save thread state
var _save_thread: Thread = null
var _pending_save_slot: int = 0
var _queued_save_slot: int = 0
var _queued_save_data: Dictionary = {}

# Async load thread state
var _load_thread: Thread = null
var _pending_load_slot: int = 0

# Async delete thread state
var _delete_thread: Thread = null
var _pending_delete_slot: int = 0

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	initialize()
	# _process is disabled by default; enabled during async save operations
	set_process(false)


func _exit_tree() -> void:
	# Ensure threads are cleaned up before this node is freed
	if _save_thread and _save_thread.is_alive():
		_save_thread.wait_to_finish()
		_save_thread = null
	if _load_thread and _load_thread.is_alive():
		_load_thread.wait_to_finish()
		_load_thread = null
	if _delete_thread and _delete_thread.is_alive():
		_delete_thread.wait_to_finish()
		_delete_thread = null


## Poll for async save/load thread completion. Only active during operations.
func _process(_delta: float) -> void:
	# Check save thread
	if _save_thread != null and not _save_thread.is_alive():
		var result: Dictionary = _save_thread.wait_to_finish()
		_save_thread = null

		if result.get("success", false):
			var slot_id: int = _pending_save_slot
			_pending_save_slot = 0
			current_state = State.IDLE
			save_completed.emit(slot_id)
			_flush_queued_save()
		else:
			var slot_id: int = _pending_save_slot
			_pending_save_slot = 0
			current_state = State.ERROR
			save_failed.emit(slot_id, result.get("error", "Unknown save error"))
			_flush_queued_save()

	# Check load thread
	if _load_thread != null and not _load_thread.is_alive():
		var result: Dictionary = _load_thread.wait_to_finish()
		_load_thread = null

		if result.get("success", false):
			var slot_id: int = _pending_load_slot
			_pending_load_slot = 0
			current_state = State.IDLE
			_distribute_loaded_data(result.get("data", {}))
			load_completed.emit(slot_id, result.get("data", {}))
		else:
			var slot_id: int = _pending_load_slot
			_pending_load_slot = 0
			current_state = State.ERROR
			load_failed.emit(slot_id, result.get("error", "Unknown load error"))

	# Check delete thread
	if _delete_thread != null and not _delete_thread.is_alive():
		var delete_result: Dictionary = _delete_thread.wait_to_finish()
		_delete_thread = null

		if delete_result.get("success", false):
			var slot_id: int = _pending_delete_slot
			_pending_delete_slot = 0
			current_state = State.IDLE
			save_deleted.emit(slot_id)
		else:
			var slot_id: int = _pending_delete_slot
			_pending_delete_slot = 0
			current_state = State.ERROR
			save_delete_failed.emit(slot_id, delete_result.get("error", "Unknown delete error"))

	# Disable polling if no active threads
	if _save_thread == null and _load_thread == null and _delete_thread == null:
		set_process(false)


## Initialize the save system: ensure save directory exists, set idle state.
func initialize() -> void:
	if not DirAccess.dir_exists_absolute(_save_dir):
		var dir_result: int = DirAccess.make_dir_recursive_absolute(_save_dir)
		if dir_result != OK:
			current_state = State.ERROR
			push_error("SaveSystem: Failed to create save directory: %s" % _save_dir)
			return

	if current_state != State.ERROR:
		current_state = State.IDLE
		print("[SaveSystem] Initialized, save directory: %s" % _save_dir)

# ── Save Data Structure ───────────────────────────────────────────────────

## Create a new SaveData dictionary with all 16 required fields at defaults.
## ADR-0005 specifies: version, timestamp, play_time_seconds, current_scene_id,
## unlocked_scenes, completed_scenes, npc_states, unlocked_spirits,
## spirit_usage_counts, has_completed_tutorial, tutorial_step (ADR-0014),
## current_dialogue_node, active_dialogue_tree_id, input_permission_state,
## settings_overrides, checksum
func _create_empty_save_data() -> Dictionary:
	return {
		"version": 1,
		"timestamp": Time.get_datetime_string_from_system(true) + "Z",  # UTC, ISO 8601
		"play_time_seconds": 0,
		"current_scene_id": "",
		"unlocked_scenes": [],
		"completed_scenes": [],
		"npc_states": {},
		"unlocked_spirits": [],
		"spirit_usage_counts": {},
		"has_completed_tutorial": false,
		"tutorial_step": 0,  # ADR-0014: tutorial progress (0=not started, 1-4=step, 5=complete)
		"current_dialogue_node": null,
		"active_dialogue_tree_id": null,
		"input_permission_state": {
			"has_mic_permission": false,
		},
		"settings_overrides": {},
		"checksum": "",
	}

# ── Checksum ──────────────────────────────────────────────────────────────

## Compute MD5 checksum for save data (excludes the checksum field itself).
## Used for integrity verification on save and load.
func _compute_checksum(data: Dictionary) -> String:
	var body: Dictionary = data.duplicate()
	body.erase("checksum")
	var json_str: String = _to_sorted_json(body)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(json_str.to_utf8_buffer())
	var hash: PackedByteArray = ctx.finish()
	return hash.hex_encode()


## Serialize a Dictionary to JSON with deterministic key ordering.
## Godot's JSON.stringify does not guarantee consistent key order across
## parse/write cycles. Sorting keys ensures checksum stability.
static func _to_sorted_json(data: Dictionary) -> String:
	var keys: PackedStringArray = data.keys()
	keys.sort()
	var entries: PackedStringArray = []
	for key in keys:
		var k: String = _json_escape_string(key)
		var v: String = _to_json_value(data[key])
		entries.append("%s: %s" % [k, v])
	return "{%s}" % ", ".join(entries)


static func _json_escape_string(s: String) -> String:
	s = s.replace("\\", "\\\\")
	s = s.replace('"', '\\"')
	s = s.replace("\n", "\\n")
	s = s.replace("\r", "\\r")
	s = s.replace("\t", "\\t")
	return '"%s"' % s


static func _to_json_value(val: Variant) -> String:
	if val is Dictionary:
		return _to_sorted_json(val)
	if val is Array:
		var items: PackedStringArray = []
		for item in val:
			items.append(_to_json_value(item))
		return "[%s]" % ", ".join(items)
	if val is String:
		return _json_escape_string(val)
	if val is bool:
		return "true" if val else "false"
	if val == null:
		return "null"
	# int or float: normalize to avoid "1" vs "1.0" differences after JSON round-trip
	if val is int:
		return str(val)
	if val is float:
		# If float represents a whole number, output without decimal
		if val == floor(val) and val < 9223372036854775807.0:
			return str(int(val))
		return str(val)
	# Other types
	return str(val)

# ── Data Collection ───────────────────────────────────────────────────────

## Collect save data from all subsystems and build a complete SaveData dict.
## Subsystems that aren't implemented yet contribute default values.

# ── Save (Public API) ────────────────────────────────────────────────────

## Save game data to the specified slot (async, non-blocking).
## Validates slot_id, computes checksum from custom_data, and writes atomically
## via a background thread. Emits save_completed or save_failed on completion.
## custom_data: Dictionary - user-provided save data ( GameManager passes its save_data)
func save(slot_id: int, custom_data: Dictionary) -> void:
	print("[SaveSystem] Saving to slot %d, data keys: %s" % [slot_id, custom_data.keys()])
	# Validate slot range
	if slot_id < 1 or slot_id > MAX_SAVE_SLOTS:
		current_state = State.ERROR
		save_failed.emit(slot_id, "Invalid slot ID: %d. Must be 1..%d" % [slot_id, MAX_SAVE_SLOTS])
		return

	# Prevent concurrent save operations
	if _save_thread != null:
		if _save_thread.is_alive():
			_queued_save_slot = slot_id
			_queued_save_data = custom_data.duplicate(true)
			return
		else:
			# Previous thread finished but wasn't cleaned up
			_save_thread.wait_to_finish()
			_save_thread = null

	current_state = State.SAVING
	_pending_save_slot = slot_id

	# Use custom_data provided by caller (e.g., GameManager)
	var save_data: Dictionary = custom_data.duplicate()
	save_data["checksum"] = _compute_checksum(save_data)

	# Launch async save on background thread
	_save_thread = Thread.new()
	_save_thread.start(_write_save_file.bind(slot_id, save_data, _save_dir))
	# Enable _process to poll for thread completion
	set_process(true)


func _flush_queued_save() -> void:
	if _queued_save_slot == 0:
		return
	var slot_id := _queued_save_slot
	var save_data := _queued_save_data.duplicate(true)
	_queued_save_slot = 0
	_queued_save_data.clear()
	save(slot_id, save_data)


## Thread function: writes save data atomically to disk.
## Returns a result dict with "success" bool and optional "error" string.
## Runs on background thread — NO SceneTree or node access allowed.
static func _write_save_file(slot_id: int, save_data: Dictionary, save_dir: String) -> Dictionary:
	var final_path: String = save_dir + "save_slot_%d.json" % slot_id
	var temp_path: String = final_path + ".tmp"

	# Serialize to JSON (use sorted keys to match checksum computation)
	var json_str: String = _to_sorted_json(save_data)
	if json_str.is_empty():
		return {"success": false, "error": "JSON serialization failed"}

	# Write to temporary file (atomic write pattern)
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		var err: int = FileAccess.get_open_error()
		return {"success": false, "error": "Failed to open temp file: %s (error %d)" % [temp_path, err]}

	if not file.store_string(json_str):
		file.close()
		return {"success": false, "error": "Failed to write save data to temp file"}

	file.close()

	# Atomically rename temp → final path
	var da: DirAccess = DirAccess.open(save_dir)
	if da == null:
		# Clean up temp file on failure
		DirAccess.remove_absolute(temp_path)
		return {"success": false, "error": "Failed to open save directory for rename"}

	var rename_result: Error = da.rename_absolute(temp_path, final_path)
	if rename_result != OK:
		# Clean up temp file on failure
		DirAccess.remove_absolute(temp_path)
		return {"success": false, "error": "Failed to rename temp file: error %d" % rename_result}

	return {"success": true}

# ── Load (Public API) ────────────────────────────────────────────────────

## Load game data from the specified slot (async, non-blocking).
## Validates slot_id, reads file, verifies version + checksum, fills missing
## fields with defaults, and distributes data to subsystems.
## Emits load_completed or load_failed on completion.
func load(slot_id: int) -> void:
	# Validate slot range
	if slot_id < 1 or slot_id > MAX_SAVE_SLOTS:
		current_state = State.ERROR
		load_failed.emit(slot_id, "Invalid slot ID: %d. Must be 1..%d" % [slot_id, MAX_SAVE_SLOTS])
		return

	# Prevent concurrent load operations
	if _load_thread != null:
		if _load_thread.is_alive():
			load_failed.emit(slot_id, "Load operation already in progress")
			return
		else:
			# Previous thread finished but wasn't cleaned up
			_load_thread.wait_to_finish()
			_load_thread = null

	# Verify file exists before launching thread
	var path: String = get_save_path(slot_id)
	if not FileAccess.file_exists(path):
		current_state = State.ERROR
		load_failed.emit(slot_id, "Save file not found: %s" % path)
		return

	current_state = State.LOADING
	_pending_load_slot = slot_id

	# Launch async load on background thread
	_load_thread = Thread.new()
	_load_thread.start(_read_save_file.bind(slot_id, path, _save_dir))
	# Enable _process to poll for thread completion
	set_process(true)


## Thread function: reads and validates save data from disk.
## Returns a result dict with "success" bool, "data" dict, or "error" string.
## Runs on background thread — NO SceneTree or node access allowed.
static func _read_save_file(slot_id: int, file_path: String, _save_dir: String) -> Dictionary:
	# Read file
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		var err: int = FileAccess.get_open_error()
		return {"success": false, "error": "Failed to open save file: %s (error %d)" % [file_path, err]}

	var json_str: String = file.get_as_text()
	file.close()

	if json_str.is_empty():
		return {"success": false, "error": "Save file is empty"}

	# Parse JSON
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_str)
	if parse_result != OK:
		return {"success": false, "error": "Invalid JSON in save file: error %d" % parse_result}

	var data: Dictionary = json.get_data()

	# Validate version
	var version: Variant = data.get("version", null)
	if version == null or version != 1:
		return {"success": false, "error": "Version mismatch: expected 1, got %s" % str(version)}

	# Validate checksum
	var stored_checksum: String = data.get("checksum", "")
	var computed_checksum: String = _compute_checksum_static(data)
	if stored_checksum != computed_checksum:
		return {"success": false, "error": "Checksum mismatch: file may be corrupted or tampered"}

	# Fill missing fields with defaults
	var validated: Dictionary = _validate_and_fill_defaults(data)

	return {"success": true, "data": validated}


## Compute MD5 checksum for save data (static version for thread use).
## Excludes the checksum field itself.
static func _compute_checksum_static(data: Dictionary) -> String:
	var body: Dictionary = data.duplicate()
	body.erase("checksum")
	var json_str: String = _to_sorted_json(body)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(json_str.to_utf8_buffer())
	var hash: PackedByteArray = ctx.finish()
	return hash.hex_encode()


## Validate save data fields and fill missing ones with defaults.
static func _validate_and_fill_defaults(data: Dictionary) -> Dictionary:
	var defaults: Dictionary = {
		"version": 1,
		"timestamp": "",
		"play_time_seconds": 0,
		"current_scene_id": "",
		"unlocked_scenes": [],
		"completed_scenes": [],
		"npc_states": {},
		"unlocked_spirits": [],
		"spirit_usage_counts": {},
		"has_completed_tutorial": false,
		"tutorial_step": 0,  # ADR-0014: tutorial progress (0=not started, 1-4=step, 5=complete)
		"current_dialogue_node": null,
		"active_dialogue_tree_id": null,
		"input_permission_state": {"has_mic_permission": false},
		"settings_overrides": {},
		"checksum": "",
	}

	# Merge: loaded data takes precedence, missing fields get defaults
	for key in defaults:
		if not data.has(key) or data[key] == null:
			data[key] = defaults[key]

	# Deep merge input_permission_state if partially missing
	if data.has("input_permission_state") and data["input_permission_state"] is Dictionary:
		var perm_defaults: Dictionary = {"has_mic_permission": false}
		for key in perm_defaults:
			if not data["input_permission_state"].has(key):
				data["input_permission_state"][key] = perm_defaults[key]

	return data


## Distribute loaded data to subsystems via signals or direct calls.
## LinguaQuest adaptation: Data is returned to caller (GameManager) via load_completed signal.
## Caller responsible for distributing data to their internal state.
func _distribute_loaded_data(data: Dictionary) -> void:
	# No subsystem distribution in LinguaQuest - GameManager handles state restoration
	# Data is available via load_completed signal payload
	pass

# ── Slot Path ─────────────────────────────────────────────────────────────

## Get the file path for a given save slot.
## Returns empty string for invalid slot IDs (must be 1..MAX_SAVE_SLOTS).
func get_save_path(slot_id: int) -> String:
	if slot_id < 1 or slot_id > MAX_SAVE_SLOTS:
		return ""
	return _save_dir + "save_slot_%d.json" % slot_id

# ── Slot Status ───────────────────────────────────────────────────────────

## Query the status of a single save slot.
func get_slot_status(slot_id: int) -> SlotStatus:
	if slot_id < 1 or slot_id > MAX_SAVE_SLOTS:
		return SlotStatus.INVALID

	var path: String = get_save_path(slot_id)
	if FileAccess.file_exists(path):
		return SlotStatus.OCCUPIED
	return SlotStatus.EMPTY

## Get status for all 3 slots at once.
## Returns { slot_id: SlotStatus } for slots 1..3.
func get_all_slot_statuses() -> Dictionary:
	var result: Dictionary = {}
	for i in range(1, MAX_SAVE_SLOTS + 1):
		result[i] = get_slot_status(i)
	return result

# ── Delete (Public API) ──────────────────────────────────────────────────

## Delete a save slot (async, non-blocking).
## Validates slot_id, checks file existence, and removes the file asynchronously.
## Deleting a non-existent slot is idempotent — emits save_deleted silently.
## Emits save_deleted(slot_id) on success, save_delete_failed on error.
func delete(slot_id: int) -> void:
	# Validate slot range
	if slot_id < 1 or slot_id > MAX_SAVE_SLOTS:
		current_state = State.ERROR
		save_failed.emit(slot_id, "Invalid slot ID: %d. Must be 1..%d" % [slot_id, MAX_SAVE_SLOTS])
		return

	# Prevent concurrent delete operations
	if _delete_thread != null:
		if _delete_thread.is_alive():
			save_delete_failed.emit(slot_id, "Delete operation already in progress")
			return
		else:
			_delete_thread.wait_to_finish()
			_delete_thread = null

	# If file doesn't exist, emit save_deleted immediately (idempotent)
	var path: String = get_save_path(slot_id)
	if not FileAccess.file_exists(path):
		current_state = State.IDLE
		save_deleted.emit(slot_id)
		return

	current_state = State.DELETING
	_pending_delete_slot = slot_id

	# Launch async delete on background thread
	_delete_thread = Thread.new()
	_delete_thread.start(_remove_save_file.bind(slot_id, path))
	# Enable _process to poll for thread completion
	set_process(true)


## Thread function: removes save file from disk.
## Returns a result dict with "success" bool and optional "error" string.
## Runs on background thread — NO SceneTree or node access allowed.
static func _remove_save_file(slot_id: int, file_path: String) -> Dictionary:
	var result: Error = DirAccess.remove_absolute(file_path)
	if result != OK:
		return {"success": false, "error": "Failed to delete save file: error %d" % result}
	return {"success": true}
