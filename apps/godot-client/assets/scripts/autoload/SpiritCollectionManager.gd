## spirit_collection_manager.gd
## Spirit Collection Manager — Core layer singleton managing word spirit unlock lifecycle
## Implements Story SC-01: 词灵解锁核心流程
## Architecture: ADR-0010 (Spirit Collection & Progress Management)
## LinguaQuest Adaptation: Uses GameManager instead of CharacterDataSystem
extends Node

# ── State Machine ──────────────────────────────────────────────────────────

enum State {
	UNINITIALIZED,
	READY,
	LOADING_SAVE,
	ACTIVE
}

var current_state: State = State.UNINITIALIZED

# ── Dependencies (LinguaQuest Adaptation) ──────────────────────────────────

var _spirit_database: Node = null      # SpiritDatabase (autoload)

# ── Signals (ADR-0010 compliant) ──────────────────────────────────────────

signal spirit_unlocked(spirit_id: String, spirit_data: Dictionary)
signal spirit_unlock_animation_finished(spirit_id: String)
signal collection_updated(progress: Dictionary)
signal usage_count_updated(spirit_id: String, new_count: int)

# ── Internal State ────────────────────────────────────────────────────────

var _unlocked_spirits: Array[String] = []
var _usage_counts: Dictionary[String, int] = {}

const USAGE_COUNT_CAP: int = 9999

# ── Score Calculation Constants ────────────────────────────────────────────

const BASE_VALUE: int = 10
const RARITY_SCORE_MULTIPLIER: Dictionary = {
	"common": 1.0,
	"rare": 2.0,
	"legendary": 5.0
}

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	# Auto-connect to SaveSystem load signal for automatic state restore
	SaveSystem.load_completed.connect(_on_save_loaded)

# ── Initialization ────────────────────────────────────────────────────────

func initialize() -> void:
	_spirit_database = SpiritDatabase
	_sync_from_game_manager()
	current_state = State.READY

func _sync_from_game_manager() -> void:
	"""从GameManager同步词灵数据"""
	_unlocked_spirits = GameManager.unlocked_spirits.duplicate()
	_usage_counts = GameManager.spirit_usage_counts.duplicate()

func _on_save_loaded(slot_id: int, data: Dictionary) -> void:
	"""存档加载完成后恢复词灵状态"""
	var spirit_data = data.get("unlocked_spirits", [])
	var usage_data = data.get("spirit_usage_counts", {})

	_unlocked_spirits.clear()
	for sid in spirit_data:
		_unlocked_spirits.append(sid)

	_usage_counts.clear()
	for sid in usage_data.keys():
		_usage_counts[sid] = usage_data[sid]

	# 同步回GameManager
	GameManager.unlocked_spirits = _unlocked_spirits.duplicate()
	GameManager.spirit_usage_counts = _usage_counts.duplicate()

	current_state = State.ACTIVE

# ── Public Unlock Interface ───────────────────────────────────────────────

func unlock_spirit(spirit_id: String, scene_id: String, keyword: String = "") -> void:
	if current_state == State.UNINITIALIZED:
		push_warning("SpiritCollectionManager: Not initialized. Call initialize() first.")
		return

	if not _spirit_database_has_spirit(spirit_id):
		push_warning("SpiritCollectionManager: Invalid spirit_id '%s'" % spirit_id)
		return

	if spirit_id in _unlocked_spirits:
		push_warning("SpiritCollectionManager: Spirit '%s' already unlocked, ignoring." % spirit_id)
		return

	var spirit_data: Dictionary = _spirit_database_get_spirit(spirit_id)
	if spirit_data.is_empty():
		push_error("SpiritCollectionManager: Failed to retrieve data for spirit '%s'" % spirit_id)
		return

	var unlock_metadata: Dictionary = {
		"spirit_id": spirit_id,
		"unlock_timestamp": Time.get_unix_time_from_system(),
		"unlock_scene": scene_id,
		"unlock_keyword": keyword,
		"usage_count": 0,
		"last_used_timestamp": 0
	}

	# LinguaQuest Adaptation: 直接更新GameManager
	_update_game_manager_spirits(unlock_metadata)

	_unlocked_spirits.append(spirit_id)

	# Trigger visual effects
	_trigger_unlock_vfx(spirit_id, scene_id)

	spirit_unlocked.emit(spirit_id, spirit_data)
	_trigger_save()
	collection_updated.emit(get_collection_progress())

# ── Internal Helpers ──────────────────────────────────────────────────────

func _spirit_database_has_spirit(spirit_id: String) -> bool:
	if _spirit_database == null:
		push_error("SpiritCollectionManager: Spirit database not set")
		return false

	if _spirit_database.has_method("get_spirit"):
		var result: Dictionary = _spirit_database.call("get_spirit", spirit_id)
		return not result.is_empty()

	push_error("SpiritCollectionManager: Database missing get_spirit method")
	return false


func _spirit_database_get_spirit(spirit_id: String) -> Dictionary:
	if _spirit_database == null:
		return {}

	if _spirit_database.has_method("get_spirit"):
		var result: Dictionary = _spirit_database.call("get_spirit", spirit_id)
		return result

	return {}


func _update_game_manager_spirits(metadata: Dictionary) -> void:
	"""LinguaQuest Adaptation: 使用GameManager替代CharacterDataSystem"""
	var spirit_id: String = metadata.get("spirit_id", "")
	if spirit_id.is_empty():
		return

	# 添加到GameManager
	if not GameManager.unlocked_spirits.has(spirit_id):
		GameManager.unlocked_spirits.append(spirit_id)
		GameManager.spirit_usage_counts[spirit_id] = 0

	# 同步到_usage_counts缓存
	_usage_counts[spirit_id] = 0


func _trigger_unlock_vfx(spirit_id: String, scene_id: String) -> void:
	"""触发词灵解锁视觉特效"""
	var spirit_data: Dictionary = _spirit_database_get_spirit(spirit_id)
	if spirit_data.is_empty():
		return

	var rarity: String = spirit_data.get("rarity", "common")
	var spawn_pos := _get_spawn_position_for_scene(scene_id)

	var effect_id: String = VFXManager.play_spirit_unlock(spawn_pos, rarity)

	if not effect_id.is_empty():
		if AudioManager.has_method("play_spirit_unlock"):
			AudioManager.call("play_spirit_unlock", rarity)

		var timer: SceneTreeTimer = get_tree().create_timer(2.0)
		timer.timeout.connect(func(): spirit_unlock_animation_finished.emit(spirit_id))
	else:
		spirit_unlock_animation_finished.emit(spirit_id)


func _get_spawn_position_for_scene(_scene_id: String) -> Vector2:
	"""根据场景ID获取特效生成位置（屏幕中心偏上）"""
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(viewport_size.x / 2.0, viewport_size.y / 3.0)


func _trigger_save() -> void:
	"""LinguaQuest Adaptation: 使用GameManager.save_progress()"""
	GameManager.save_progress()

# ── Public Query Interface ────────────────────────────────────────────────

func get_unlocked_spirits() -> Array[String]:
	return _unlocked_spirits.duplicate()


func is_spirit_unlocked(spirit_id: String) -> bool:
	return spirit_id in _unlocked_spirits


func get_current_state() -> State:
	return current_state

# ── Usage Count Tracking ───────────────────────────────────────────────────

func increment_usage(spirit_id: String) -> void:
	if spirit_id not in _unlocked_spirits:
		return

	if _usage_counts.has(spirit_id):
		var count: int = _usage_counts[spirit_id]
		if count >= USAGE_COUNT_CAP:
			push_warning("SpiritCollectionManager: Usage count cap reached for '%s'" % spirit_id)
			return
		_usage_counts[spirit_id] = count + 1
	else:
		_usage_counts[spirit_id] = 1

	# 同步到GameManager
	GameManager.spirit_usage_counts[spirit_id] = _usage_counts[spirit_id]
	usage_count_updated.emit(spirit_id, _usage_counts[spirit_id])


func get_usage_count(spirit_id: String) -> int:
	return _usage_counts.get(spirit_id, 0)


func set_usage_count(spirit_id: String, count: int) -> void:
	_usage_counts[spirit_id] = count
	GameManager.spirit_usage_counts[spirit_id] = count

# ── Progress Calculation ───────────────────────────────────────────────────

func get_collection_progress() -> Dictionary:
	if _spirit_database == null:
		push_error("SpiritCollectionManager: Spirit database not set")
		return {"unlocked_count": 0, "total_count": 0, "progress_percent": 0.0}

	var all_spirits: Array[Dictionary] = _spirit_database.get_all_spirits()
	var total_count: int = all_spirits.size()
	var unlocked_count: int = _unlocked_spirits.size()

	var progress_percent: float = 0.0
	if total_count > 0:
		progress_percent = float(unlocked_count) / total_count * 100.0

	return {
		"unlocked_count": unlocked_count,
		"total_count": total_count,
		"progress_percent": progress_percent
	}


func get_category_progress() -> Dictionary:
	if _spirit_database == null:
		push_error("SpiritCollectionManager: Spirit database not set")
		return {}

	var progress: Dictionary = {}
	var all_spirits: Array[Dictionary] = _spirit_database.get_all_spirits()

	var categories: Dictionary[String, bool] = {}
	for spirit in all_spirits:
		var cat: String = spirit.get("category", "")
		if not cat.is_empty():
			categories[cat] = true

	for category in categories.keys():
		var total_in_cat: int = 0
		for spirit in all_spirits:
			if spirit.get("category") == category:
				total_in_cat += 1

		var unlocked_in_cat: int = 0
		for sid in _unlocked_spirits:
			var spirit_data: Dictionary = _spirit_database.get_spirit(sid)
			if spirit_data.get("category") == category:
				unlocked_in_cat += 1

		var cat_progress: float = 0.0
		if total_in_cat > 0:
			cat_progress = float(unlocked_in_cat) / total_in_cat * 100.0

		progress[category] = {
			"unlocked": unlocked_in_cat,
			"total": total_in_cat,
			"progress_percent": cat_progress
		}

	return progress


func restore_from_save(state: Dictionary) -> void:
	current_state = State.LOADING_SAVE

	_unlocked_spirits.clear()
	_usage_counts.clear()

	var invalid_ids: PackedStringArray = []
	for spirit_id in state.get("unlocked_spirits", []):
		if not _spirit_database_has_spirit(spirit_id):
			invalid_ids.append(spirit_id)
			push_warning("SpiritCollectionManager: Skipping unknown spirit_id '%s' from save data" % spirit_id)
			continue
		_unlocked_spirits.append(spirit_id)

	var usage: Dictionary = state.get("spirit_usage_counts", {})
	for spirit_id in _unlocked_spirits:
		if usage.has(spirit_id):
			_usage_counts[spirit_id] = usage[spirit_id]

	# 同步回GameManager
	GameManager.unlocked_spirits = _unlocked_spirits.duplicate()
	GameManager.spirit_usage_counts = _usage_counts.duplicate()

	current_state = State.ACTIVE

	if not invalid_ids.is_empty():
		push_warning("SpiritCollectionManager: %d invalid spirit_id(s) skipped during restore" % invalid_ids.size())


func get_save_snapshot() -> Dictionary:
	return {
		"unlocked_spirits": _unlocked_spirits.duplicate(),
		"spirit_usage_counts": _usage_counts.duplicate()
	}


func get_score_contribution(spirit_id: String) -> int:
	if _spirit_database == null:
		return BASE_VALUE

	var spirit_data: Dictionary = _spirit_database.get_spirit(spirit_id)
	if spirit_data.is_empty():
		return BASE_VALUE

	var rarity: String = spirit_data.get("rarity", "common")
	var multiplier: float = RARITY_SCORE_MULTIPLIER.get(rarity, 1.0)

	return int(float(BASE_VALUE) * multiplier)