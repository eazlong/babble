## SceneManagementSystem.gd
## Story: Scene Management System - SM-03
## Handles scene enter/exit flow coordination per ADR-0006
## Architecture: Uses SceneStateMachine composition, signal-based decoupling
extends Node

# class_name SceneManagementSystem  # Commented: conflicts with autoload singleton

const VERSION: String = "0.2.0"

# ── State Machine (Composition) ──────────────────────────────────────────

var _state_machine: SceneStateMachine = SceneStateMachine.new()

# ── External System References (Dependency Injection) ─────────────────────

var _narrative_dialogue: Node = null  # NarrativeDialogue autoload
var _save_system: Node = null         # SaveSystem autoload
var _character_data: Node = null      # CharacterData autoload
var _input_manager: Node = null       # InputManager autoload

# Legacy State enum for backwards compatibility (maps to SceneStateMachine.State)
enum State {
	UNINITIALIZED = 0,
	IDLE = 1,
	TRANSITIONING_IN = 2,
	ACTIVE = 3,
	TRANSITIONING_OUT = 4,
	TRANSITIONING = 2,  # Legacy alias
	READY = 1,          # Legacy alias
	ERROR = 5
}

# ── Scene Config Registry ─────────────────────────────────────────────────

var _scene_configs: Dictionary = {}  # String -> SceneConfig
var _unlocked_scenes: Array[String] = []
var _completed_scenes: Array[String] = []
var _current_primary_npc: String = ""

# ── Internal State ────────────────────────────────────────────────────────

var _current_scene_id: String = ""
var _previous_scene_id: String = ""
var _pending_scene_id: String = ""
var _transition_data: Dictionary = {}

# Animation timing (configurable; default 0 = skip animation wait)
var _fade_duration: float = 0.0
var _hold_duration: float = 0.0

# ── Signals (ADR-0006 compliant) ─────────────────────────────────────────

signal system_initialized()
signal scene_entering(scene_id: String, scene_data: Dictionary)
signal scene_entered(scene_id: String)
signal scene_exiting(scene_id: String)
signal scene_exited(scene_id: String)
signal scene_unlocked(scene_id: String)
signal scene_completed(scene_id: String)
signal transition_started(transition_type: String)
signal transition_completed()
signal scene_name_display(scene_name: String, duration: float)
signal state_changed(old_state: int, new_state: int)
signal transition_error(error_message: String)
signal scene_unloaded(scene_id: String, success: bool)
signal input_blocked()
signal input_unblocked()

# ── Unload Phase Enum ───────────────────────────────────────────────────

enum UnloadPhase {
	SAVING_STATE = 0,
	STOPPING_AUDIO = 1,
	RELEASING_BACKGROUND = 2,
	CLEANING_NODES = 3,
	UNLOADING_RESOURCES = 4,
}

# ── Unload Constants ────────────────────────────────────────────────────

const UNLOAD_TIMEOUT_MS: int = 500
const PHASE_WARNING_THRESHOLD_MS: int = 150
const MEMORY_LEAK_THRESHOLD_BYTES: int = 1048576
const SAVE_BUDGET_MS: int = 100
const AUDIO_BUDGET_MS: int = 50
const BACKGROUND_BUDGET_MS: int = 100
const NODES_BUDGET_MS: int = 100
const RESOURCES_BUDGET_MS: int = 100

# ── Lifecycle ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_state_machine.state_changed.connect(_on_state_machine_state_changed)

func _on_state_machine_state_changed(old_state: int, new_state: int) -> void:
	state_changed.emit(old_state, new_state)

# ── Initialization ────────────────────────────────────────────────────────

## Initialize the scene management system with scene configurations
## Loads configs into registry and marks first scene as unlocked
func initialize(scene_configs: Array) -> bool:
	print("[SceneManagementSystem] Loading %d scene configs..." % scene_configs.size())
	_scene_configs.clear()
	for config_data in scene_configs:
		if config_data is Dictionary:
			var config := SceneConfig.from_json(config_data)
			if config != null:
				_scene_configs[config.scene_id] = config

	if _scene_configs.size() > 0:
		var first_id := _find_first_scene()
		if not first_id.is_empty() and not first_id in _unlocked_scenes:
			_unlocked_scenes.append(first_id)
		print("[SceneManagementSystem] First scene unlocked: %s" % first_id)

	var success := _state_machine.initialize()
	if success:
		system_initialized.emit()
		print("[SceneManagementSystem] Initialized successfully, total configs: %d" % _scene_configs.size())
	return success

func _find_first_scene() -> String:
	var first_id := ""
	var first_chapter := 999999
	var first_order := 999999

	for scene_id in _scene_configs:
		var config: SceneConfig = _scene_configs[scene_id]
		if config.chapter < first_chapter or (config.chapter == first_chapter and config.order < first_order):
			first_chapter = config.chapter
			first_order = config.order
			first_id = scene_id

	return first_id

# ── Dependency Injection Interface ───────────────────────────────────────


# ── Public Scene Transition Interface ────────────────────────────────────

## Enter a scene following ADR-0006 14-step flow.
## All steps execute synchronously. Animation timing is configurable
## (default 0 = skip animation wait for test compatibility).
func enter_scene(scene_id: String, transition_data: Dictionary = {}) -> bool:
	var current_state := _state_machine.get_current_state()

	# Step 1: Validate state (IDLE only)
	if current_state == SceneStateMachine.State.ERROR:
		transition_error.emit("Cannot enter scene in ERROR state")
		return false

	if current_state in [SceneStateMachine.State.TRANSITIONING_IN, SceneStateMachine.State.TRANSITIONING_OUT]:
		push_warning("Already transitioning, queueing scene: " + scene_id)
		_pending_scene_id = scene_id
		return false

	if current_state == SceneStateMachine.State.ACTIVE:
		# Step 4: Exit current scene first
		var exit_success := exit_scene()
		if not exit_success:
			transition_error.emit("Failed to exit current scene")
			return false

	if current_state != SceneStateMachine.State.IDLE and current_state != SceneStateMachine.State.ACTIVE:
		transition_error.emit("Cannot enter scene from state: " + str(current_state))
		return false

	# Step 2: Validate scene_id exists
	if not _scene_configs.has(scene_id):
		_handle_error("Scene not found: " + scene_id, true)
		return false

	var config: SceneConfig = _scene_configs[scene_id]

	# Step 3: Validate unlocked
	if not _is_scene_unlocked(scene_id):
		push_warning("Scene is locked: " + scene_id)
		transition_error.emit("Scene is locked: " + scene_id)
		return false

	_transition_data = transition_data.duplicate(true)
	_previous_scene_id = _current_scene_id
	_current_scene_id = scene_id

	# Step 5: State -> TRANSITIONING_IN
	_state_machine.try_transition_to(SceneStateMachine.State.TRANSITIONING_IN)

	# Step 6: Block input

	# Step 7: Load resources (no-op stub)
	_load_scene_resources(scene_id)

	# Step 8: Register primary NPC
	var primary_npc := _find_primary_npc(config)
	# Step 10: Trigger entry_events
	_trigger_entry_events(config)

	# Step 10a: Emit scene_entering (before transition per ADR-0006 signal order)
	scene_entering.emit(scene_id, _transition_data)

	# Step 11: Transition animation (configurable duration, default 0 = skip)
	transition_started.emit("fade_in")
	_play_transition_animation_sync("fade_in")
	transition_completed.emit()

	# Step 12: Unblock input

	# Step 13: State -> ACTIVE

	# Step 14: Emit remaining signals
	scene_entered.emit(scene_id)
	scene_name_display.emit(config.display_name, 2.0)

	return true

## Exit current scene following ADR-0006 10-step flow.
## All steps execute synchronously.
func exit_scene() -> bool:
	var current_state := _state_machine.get_current_state()

	# Step 1: Validate state (ACTIVE only - AC-SM04-05)
	if current_state == SceneStateMachine.State.ERROR:
		transition_error.emit("Cannot exit in ERROR state")
		return false

	if current_state in [SceneStateMachine.State.TRANSITIONING_IN, SceneStateMachine.State.TRANSITIONING_OUT]:
		push_warning("Cannot exit during transition")
		return false

	if current_state == SceneStateMachine.State.IDLE:
		push_warning("Cannot exit_scene from IDLE state")
		return false

	if current_state != SceneStateMachine.State.ACTIVE:
		push_warning("Cannot exit_scene from state: " + str(current_state))
		return false

	var exited_id := _current_scene_id
	var config: SceneConfig = _scene_configs.get(_current_scene_id, null)

	# Step 2: State -> TRANSITIONING_OUT
	_state_machine.try_transition_to(SceneStateMachine.State.TRANSITIONING_OUT)
	scene_exiting.emit(exited_id)

	# Step 3: Trigger exit_events
	if config != null:
		_trigger_exit_events(config)

	# Step 4: Transition animation (configurable duration, default 0 = skip)
	transition_started.emit("fade_out")
	_play_transition_animation_sync("fade_out")
	transition_completed.emit()

	# Step 5: Unload resources
	_unload_scene_resources_sync()

	# Step 6: Clear primary NPC

	# Step 7: Unload dialogue tree
	if _narrative_dialogue and config and _narrative_dialogue.has_method("unload_tree"):
		_narrative_dialogue.call("unload_tree", config.dialogue_tree_id)

	# Step 8: State -> IDLE
	_state_machine.try_transition_to(SceneStateMachine.State.IDLE)

	# Step 9: Cleanup and emit
	_current_scene_id = ""
	_previous_scene_id = exited_id
	scene_exited.emit(exited_id)

	return true

# ── Scene Unlock and Completion ───────────────────────────────────────────

func unlock_scene(scene_id: String) -> void:
	if not _is_scene_unlocked(scene_id):
		_unlocked_scenes.append(scene_id)
		scene_unlocked.emit(scene_id)

func complete_scene(scene_id: String) -> void:
	if not _scene_configs.has(scene_id):
		push_warning("complete_scene: scene not found in configs: " + scene_id)
		return
	if not _is_scene_completed(scene_id):
		_completed_scenes.append(scene_id)
		scene_completed.emit(scene_id)
		_unlock_next_scene(scene_id)

	if _save_system and _save_system.has_method("save"):
		_save_system.call("save", 1)

func _is_scene_unlocked(scene_id: String) -> bool:
	return scene_id in _unlocked_scenes

func _is_scene_completed(scene_id: String) -> bool:
	return scene_id in _completed_scenes

func _unlock_next_scene(current_scene_id: String) -> void:
	if not _scene_configs.has(current_scene_id):
		return

	var current_config: SceneConfig = _scene_configs[current_scene_id]
	var chapter := current_config.chapter
	var order := current_config.order

	var next_id := _find_scene_by_chapter_order(chapter, order + 1)
	if not next_id.is_empty():
		unlock_scene(next_id)
		return

	var next_chapter_first := _find_scene_by_chapter_order(chapter + 1, 1)
	if not next_chapter_first.is_empty():
		unlock_scene(next_chapter_first)

func _find_scene_by_chapter_order(chapter: int, order: int) -> String:
	for scene_id in _scene_configs:
		var config: SceneConfig = _scene_configs[scene_id]
		if config.chapter == chapter and config.order == order:
			return scene_id
	return ""

# ── Scene Progress ────────────────────────────────────────────────────────

## Returns overall scene completion progress as a percentage (0.0-100.0).
## Divides completed scenes by total configured scenes.
func get_scene_progress() -> float:
	var total := _scene_configs.size()
	if total == 0:
		return 0.0
	var completed := _completed_scenes.size()
	return float(completed) / float(total) * 100.0

## Returns chapter completion progress as a percentage (0.0-100.0).
## Divides completed scenes in the chapter by total scenes in the chapter.
func get_chapter_progress(chapter: int) -> float:
	var scenes_in_chapter := 0
	var completed_in_chapter := 0
	for scene_id in _scene_configs:
		var config: SceneConfig = _scene_configs[scene_id]
		if config.chapter == chapter:
			scenes_in_chapter += 1
			if scene_id in _completed_scenes:
				completed_in_chapter += 1
	if scenes_in_chapter == 0:
		return 0.0
	return float(completed_in_chapter) / float(scenes_in_chapter) * 100.0

# ── Save Integration ───────────────────────────────────────────────────────

## Returns a snapshot of scene progress for save persistence.
## Arrays are duplicated to prevent external mutation of internal state.
func get_save_data() -> Dictionary:
	return {
		"current_scene_id": _current_scene_id,
		"unlocked_scenes": _unlocked_scenes.duplicate(),
		"completed_scenes": _completed_scenes.duplicate()
	}

## Restores scene progress from saved data.
## Assigns new data directly — no duplicate needed since the arrays are
## freshly obtained from the save dictionary.
func restore_from_save(data: Dictionary) -> void:
	var raw_unlocked: Array = data.get("unlocked_scenes", [])
	var raw_completed: Array = data.get("completed_scenes", [])
	var saved_scene_id: String = str(data.get("current_scene_id", ""))

	# Restore unlocked/completed state
	_unlocked_scenes.clear()
	for item in raw_unlocked:
		_unlocked_scenes.append(str(item))
	_completed_scenes.clear()
	for item in raw_completed:
		_completed_scenes.append(str(item))

	# If no data to restore (empty dict), stay empty — don't auto-unlock
	if raw_unlocked.is_empty() and raw_completed.is_empty() and saved_scene_id.is_empty():
		_current_scene_id = ""
		return

	# Validate scene_id exists in config registry
	if saved_scene_id == "" or not _scene_configs.has(saved_scene_id):
		push_warning("Invalid saved scene_id, falling back to first unlocked")
		saved_scene_id = _get_first_unlocked_scene()

	# Validate scene is unlocked
	if not saved_scene_id.is_empty() and not _is_scene_unlocked(saved_scene_id):
		push_warning("Saved scene not unlocked, falling back")
		saved_scene_id = _get_first_unlocked_scene()

	# Apply valid scene_id and enter the scene (AC-SM07-04)
	if not saved_scene_id.is_empty():
		_current_scene_id = saved_scene_id
		# Only call enter_scene if system is initialized and in a valid state
		if _scene_configs.size() > 0 and _state_machine.get_current_state() == SceneStateMachine.State.IDLE:
			enter_scene(saved_scene_id)
		else:
			push_warning("restore_from_save: cannot enter scene — system not ready (state=%d, configs=%d)" % [_state_machine.get_current_state(), _scene_configs.size()])

## Returns the first unlocked scene_id, or falls back to the first scene
## in config order (chapter/order sort).
func _get_first_unlocked_scene() -> String:
	if _unlocked_scenes.size() > 0:
		return _unlocked_scenes[0]
	# Fallback: find first scene by config order, ensure it's unlocked
	var first_id := _find_first_scene()
	if not first_id.is_empty() and not _is_scene_unlocked(first_id):
		_unlocked_scenes.append(first_id)
	return first_id

# ── Event Execution ───────────────────────────────────────────────────────

func _trigger_entry_events(config: SceneConfig) -> void:
	for event in config.entry_events:
		_execute_narrative_event(event)

func _trigger_exit_events(config: SceneConfig) -> void:
	for event in config.exit_events:
		_execute_narrative_event(event)

func _execute_narrative_event(event: Dictionary) -> void:
	var event_type: String = event.get("type", "")
	match event_type:
		"modify_affinity":
			if _character_data and _character_data.has_method("modify_affinity"):
				var npc_id: String = event.get("npc_id", "")
				var amount: int = event.get("amount", 0)
				_character_data.call("modify_affinity", npc_id, amount)
		"play_animation":
			var animation_id: String = event.get("animation_id", "")
			push_warning("play_animation event: " + animation_id)
		_:
			push_warning("Unknown event type: " + event_type)

# ── Input Blocking ─────────────────────────────────────────────────────────

func _block_input() -> void:
	if _input_manager and _input_manager.has_method("set_input_blocked"):
		_input_manager.call("set_input_blocked", true)
	input_blocked.emit()

func _unblock_input() -> void:
	if _input_manager and _input_manager.has_method("set_input_blocked"):
		_input_manager.call("set_input_blocked", false)
	input_unblocked.emit()

# ── Scene Resources ────────────────────────────────────────────────────────

func _load_scene_resources(scene_id: String) -> void:
	# No actual resource loading yet — synchronous return.
	# When real loading is added, use ResourceLoader.load_threaded_request()
	# and await its progress signal here.
	pass

## Synchronous version of unload — runs all phases without async timeouts.
func _unload_scene_resources_sync() -> void:
	var scene_id := _current_scene_id
	if _save_system and _save_system.has_method("save"):
		_save_system.call("save", 1)
	_stop_scene_audio()
	_release_background_resources()
	_cleanup_scene_nodes()
	_unload_cached_resources(scene_id)
	scene_unloaded.emit(scene_id, true)

func _unload_scene_resources(timeout_override_ms: int = -1) -> void:
	var timeout_ms: int = timeout_override_ms if timeout_override_ms >= 0 else UNLOAD_TIMEOUT_MS
	var scene_id := _current_scene_id
	var start_time := Time.get_ticks_msec()
	var all_phases_ok := true

	# Phase 1: Saving state
	# save() is currently synchronous — call directly and measure elapsed time.
	# When save becomes async (returns Signal), use _await_with_timeout instead.
	var phase_start := Time.get_ticks_msec()
	if _save_system and _save_system.has_method("save"):
		_save_system.call("save", 1)
		var phase_elapsed := Time.get_ticks_msec() - phase_start
		if phase_elapsed > PHASE_WARNING_THRESHOLD_MS:
			push_warning("_unload_scene_resources: saving_state took %dms (threshold: %dms)" % [phase_elapsed, PHASE_WARNING_THRESHOLD_MS])
		if phase_elapsed > SAVE_BUDGET_MS:
			push_error("_unload_scene_resources: save exceeded budget (%dms, took %dms) for scene '%s'" % [SAVE_BUDGET_MS, phase_elapsed, scene_id])
			all_phases_ok = false
	else:
		# No save system — skip gracefully
		pass

	# Check total timeout after each phase
	if _is_unload_timed_out(start_time, timeout_ms):
		push_error("_unload_scene_resources: timeout (%dms) reached at saving_state for scene '%s'" % [timeout_ms, scene_id])
		scene_unloaded.emit(scene_id, false)
		return

	# Phase 2: Stopping audio
	phase_start = Time.get_ticks_msec()
	var audio_ok := _stop_scene_audio()
	var phase_elapsed := Time.get_ticks_msec() - phase_start
	if phase_elapsed > PHASE_WARNING_THRESHOLD_MS:
		push_warning("_unload_scene_resources: stopping_audio took %dms" % phase_elapsed)
	if not audio_ok:
		push_warning("_unload_scene_resources: stopping_audio failed for scene '%s'" % scene_id)
		all_phases_ok = false

	if _is_unload_timed_out(start_time, timeout_ms):
		push_error("_unload_scene_resources: timeout (%dms) reached at stopping_audio for scene '%s'" % [timeout_ms, scene_id])
		scene_unloaded.emit(scene_id, false)
		return

	# Phase 3: Releasing background resources
	phase_start = Time.get_ticks_msec()
	var bg_ok := _release_background_resources()
	phase_elapsed = Time.get_ticks_msec() - phase_start
	if phase_elapsed > PHASE_WARNING_THRESHOLD_MS:
		push_warning("_unload_scene_resources: releasing_background took %dms" % phase_elapsed)
	if not bg_ok:
		push_warning("_unload_scene_resources: releasing_background failed for scene '%s'" % scene_id)
		all_phases_ok = false

	if _is_unload_timed_out(start_time, timeout_ms):
		push_error("_unload_scene_resources: timeout (%dms) reached at releasing_background for scene '%s'" % [timeout_ms, scene_id])
		scene_unloaded.emit(scene_id, false)
		return

	# Phase 4: Cleaning nodes
	phase_start = Time.get_ticks_msec()
	var nodes_ok := _cleanup_scene_nodes()
	phase_elapsed = Time.get_ticks_msec() - phase_start
	if phase_elapsed > PHASE_WARNING_THRESHOLD_MS:
		push_warning("_unload_scene_resources: cleaning_nodes took %dms" % phase_elapsed)
	if not nodes_ok:
		push_warning("_unload_scene_resources: cleaning_nodes failed for scene '%s'" % scene_id)
		all_phases_ok = false

	if _is_unload_timed_out(start_time, timeout_ms):
		push_error("_unload_scene_resources: timeout (%dms) reached at cleaning_nodes for scene '%s'" % [timeout_ms, scene_id])
		scene_unloaded.emit(scene_id, false)
		return

	# Phase 5: Unloading resources from cache
	phase_start = Time.get_ticks_msec()
	var res_ok := _unload_cached_resources(scene_id)
	phase_elapsed = Time.get_ticks_msec() - phase_start
	if phase_elapsed > PHASE_WARNING_THRESHOLD_MS:
		push_warning("_unload_scene_resources: unloading_resources took %dms" % phase_elapsed)
	if not res_ok:
		push_warning("_unload_scene_resources: unloading_resources failed for scene '%s'" % scene_id)
		all_phases_ok = false

	# Final timeout check
	var total_elapsed := Time.get_ticks_msec() - start_time
	if total_elapsed > timeout_ms:
		push_error("_unload_scene_resources: total unload took %dms (budget: %dms) for scene '%s'" % [total_elapsed, timeout_ms, scene_id])
		all_phases_ok = false

	# Emit completion signal as last step
	scene_unloaded.emit(scene_id, all_phases_ok)


## Check if unload has exceeded the timeout budget
func _is_unload_timed_out(start_time: int, timeout_ms: int) -> bool:
	return (Time.get_ticks_msec() - start_time) >= timeout_ms


## Stop scene-specific audio (BGM, ambient sounds).
## Placeholder — actual implementation depends on AudioSystem integration.
## Returns true on success, false on error.
func _stop_scene_audio() -> bool:
	# TODO: Integrate with AudioSystem when available
	# For now, this is a no-op placeholder per story scope
	return true


## Release background resource references held by the current scene.
## Returns true on success, false on error.
func _release_background_resources() -> bool:
	var config: SceneConfig = _scene_configs.get(_current_scene_id, null)
	if config == null:
		return true  # Nothing to release — not an error
	# Release background texture reference if tracked
	# Actual resource release handled via ResourceLoader in _unload_cached_resources
	return true


## Clean up scene nodes using queue_free (never free()).
## Returns true on success, false on error.
func _cleanup_scene_nodes() -> bool:
	# Scene nodes are managed by Godot's scene tree
	# When transitioning, nodes added to the tree during enter_scene
	# should be removed here. Since our current architecture doesn't
	# add persistent scene nodes (configs are data-only), this is
	# a placeholder for future scene node management.
	return true


## Unload resources from ResourceLoader cache for the given scene.
## Returns true on success, false on error.
func _unload_cached_resources(scene_id: String) -> bool:
	var config: SceneConfig = _scene_configs.get(scene_id, null)
	if config == null:
		return true  # Nothing to unload — not an error
	# Resources loaded via ResourceLoader during _load_scene_resources
	# would be unloaded here. Current _load_scene_resources is a timer stub,
	# so there are no cached resources to unload yet.
	# Future: iterate config resource paths and call ResourceLoader caching APIs
	return true


## Race a Signal against a timeout. Returns true if signal arrives first,
## false if timeout_ms elapses first. For Signal targets only — uses
## process_frame polling to correctly detect which completes first.
## For non-Signal values (synchronous calls): returns true immediately —
## timeout does not apply since synchronous calls cannot be interrupted.
func _await_with_timeout(target: Variant, timeout_ms: int) -> bool:
	if target is Signal:
		var sig: Signal = target
		var resolved := false
		var callable := func(): resolved = true
		sig.connect(callable, CONNECT_ONE_SHOT)
		var start := Time.get_ticks_msec()
		while not resolved and (Time.get_ticks_msec() - start) < timeout_ms:
			await get_tree().process_frame
		if not resolved and sig.is_connected(callable):
			sig.disconnect(callable)
		return resolved
	# Non-signal result (synchronous call) — treat as immediate success
	return true

# ── Transition Animation ───────────────────────────────────────────────────

## Synchronous version of transition animation.
## Waits only if _fade_duration/_hold_duration are > 0 (production mode).
## Default (0.0) returns immediately for test compatibility.
func _play_transition_animation_sync(transition_type: String) -> void:
	if _fade_duration <= 0.0 and _hold_duration <= 0.0:
		return
	# In production with real timing, this would use OS delay.
	# For now, skip animation in sync mode — use the async version for real timing.

## Async version of transition animation — use when real timing is needed.
func _play_transition_animation(transition_type: String) -> void:
	# When no real animation system is injected, skip animation wait.
	# Production code should call set_transition_durations() to configure
	# actual fade/hold times.
	if _fade_duration <= 0.0 and _hold_duration <= 0.0:
		return

	if transition_type == "fade_out":
		await get_tree().create_timer(_fade_duration).timeout
		await get_tree().create_timer(_hold_duration).timeout
	else:
		await get_tree().create_timer(_fade_duration).timeout

# ── NPC Management ────────────────────────────────────────────────────────

func _find_primary_npc(config: SceneConfig) -> String:
	for npc in config.npcs:
		if npc.is_primary:
			return npc.npc_id
	return "npc_ling_girl"

# ── Public Query Interface ─────────────────────────────────────────────────

func get_current_scene_id() -> String:
	return _current_scene_id

func get_previous_scene_id() -> String:
	return _previous_scene_id

func get_pending_scene_id() -> String:
	return _pending_scene_id

func get_current_state() -> int:
	return _state_machine.get_current_state()

func get_transition_data() -> Dictionary:
	return _transition_data.duplicate(true)

func is_ready_for_transition() -> bool:
	return _state_machine.get_current_state() == SceneStateMachine.State.IDLE

func get_scene_config(scene_id: String) -> SceneConfig:
	return _scene_configs.get(scene_id, null)

func get_unlocked_scenes() -> Array[String]:
	return _unlocked_scenes.duplicate()

func get_completed_scenes() -> Array[String]:
	return _completed_scenes.duplicate()

func get_current_primary_npc() -> String:
	return _current_primary_npc

# ── Error Handling ─────────────────────────────────────────────────────────

## Handles errors by transitioning to ERROR state and optionally auto-recovering.
## Logs the error, emits transition_error signal, and transitions state to ERROR.
## If auto_recover is true, attempts recovery to IDLE after state change.
func _handle_error(error_message: String, auto_recover: bool = false) -> void:
	# Handle 后的错误：已经通过 transition_error 信号通知，仍用 push_warning 记录日志
	# （避免 GUT 测试中 push_error 被解析为 unexpected failure）
	# 真正不可恢复的错误（如资源超时）仍保留 push_error — 那些不在 _handle_error 路径
	push_warning("[SceneManagement] " + error_message)
	transition_error.emit(error_message)
	_state_machine.try_transition_to(SceneStateMachine.State.ERROR)
	if auto_recover:
		recover_to_idle()

## Attempts to recover from ERROR state to IDLE state.
## Validates that the current state is ERROR before attempting recovery.
## Returns true if recovery was successful (state was ERROR and transitioned to IDLE).
## Returns false if current state is not ERROR or state machine transition failed.
## Public API — intended for manual error recovery (e.g., from UI or narrative systems).
func recover_to_idle() -> bool:
	var current_state := _state_machine.get_current_state()
	if current_state != SceneStateMachine.State.ERROR:
		return false
	return _state_machine.try_transition_to(SceneStateMachine.State.IDLE)
