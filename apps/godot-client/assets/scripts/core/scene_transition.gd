class_name SceneTransition
extends Node

## 场景转换编排器 (Story SM-11)
## 负责编排完整的场景切换流程：退出当前场景 → 淡出 → 卸载 → 加载 → 淡入 → 进入新场景
## 管理转换队列、进度追踪、超时检测和输入屏蔽

signal transition_progress_changed(progress: int)
signal transition_started(from_scene: String, to_scene: String)
signal transition_completed(to_scene: String)
signal transition_failed(scene_id: String, reason: String)
signal transition_timeout_reached(scene_id: String)

enum TransitionState {
	IDLE,
	REQUESTED,
	EXITING,
	FADING_OUT,
	BLACK_SCREEN,
	UNLOADING,
	LOADING,
	FADING_IN,
	ENTERING,
	COMPLETED,
	ERROR
}

enum TransitionError {
	NONE = 0,
	SAME_SCENE = 1,
	SCENE_NOT_FOUND = 2,
	SCENE_LOCKED = 3,
	TIMEOUT = 4,
	QUEUE_FULL = 5,
	UNKNOWN = 99
}

# ── Constants ──────────────────────────────────────────────────────────────

const FADE_OUT_DURATION: float = 0.5
const BLACK_SCREEN_DURATION: float = 0.3
const FADE_IN_DURATION: float = 0.5
const ANIMATION_TOTAL: float = 1.3

const TRANSITION_TIMEOUT_MS: int = 5000
const PROGRESS_UPDATE_INTERVAL_MS: int = 50
const LOADING_COMPLETE_STAGE: int = 5  # LoadingStage.LOADED
const MAX_QUEUE_SIZE: int = 2

const PHASE_WEIGHT_EXITING: float = 0.1
const PHASE_WEIGHT_FADING_OUT: float = 0.15
const PHASE_WEIGHT_BLACK_SCREEN: float = 0.1
const PHASE_WEIGHT_UNLOADING: float = 0.15
const PHASE_WEIGHT_LOADING: float = 0.25
const PHASE_WEIGHT_FADING_IN: float = 0.15
const PHASE_WEIGHT_ENTERING: float = 0.1

# ── State ──────────────────────────────────────────────────────────────────

var _state: TransitionState = TransitionState.IDLE
var _current_scene_id: String = ""
var _pending_scene_id: String = ""
var _queue: Array[String] = []
var _is_transitioning: bool = false
var _transition_start_time: int = 0
var _last_progress_time: int = 0
var _current_progress: int = 0

# ── Dependencies ───────────────────────────────────────────────────────────

var _scene_system: Node = null
var _scene_loader: Object = null
var _transition_manager: Object = null
var _input_manager: Node = null

# ── Internal ───────────────────────────────────────────────────────────────

var _completed_phases: Array[String] = []
var _error_code: TransitionError = TransitionError.NONE

# ── Lifecycle ──────────────────────────────────────────────────────────────

func _exit_tree() -> void:
	if _is_transitioning:
		_is_transitioning = false
		_state = TransitionState.ERROR
		if _input_manager and _input_manager.has_method("set_input_blocked"):
			_input_manager.call("set_input_blocked", false)


# ── Public API ─────────────────────────────────────────────────────────────

## 请求场景转换
## scene_id: 目标场景ID
## 返回: true 如果请求被接受，false 如果被拒绝
func request_transition(scene_id: String) -> bool:
	if scene_id.is_empty():
		push_error("SceneTransition: scene_id cannot be empty")
		return false

	# AC-07: 相同场景切换（包括正在转换中的同场景请求）
	if scene_id == _current_scene_id:
		if not _is_transitioning:
			push_warning("SceneTransition: Requested transition to current scene '%s' — skipping" % scene_id)
			transition_completed.emit(scene_id)
			return true
		## If already transitioning, reject same-scene request silently
		return true

	# 验证场景是否存在
	if _scene_system and _scene_system.has_method("get_scene_config"):
		var config = _scene_system.call("get_scene_config", scene_id)
		if config == null:
			push_warning("SceneTransition: Scene '%s' does not exist — rejected" % scene_id)
			return false

	# 队列已满检查
	if _queue.size() >= MAX_QUEUE_SIZE and _is_transitioning:
		push_warning("SceneTransition: Queue full (%d), replacing last entry" % MAX_QUEUE_SIZE)
		if _queue.size() > 0:
			_queue.remove_at(_queue.size() - 1)
		_queue.append(scene_id)
		_pending_scene_id = scene_id
		return true

	# 正在转换中 - 加入队列
	if _is_transitioning:
		_queue.append(scene_id)
		_pending_scene_id = scene_id
		print("SceneTransition: Queued transition to '%s' (queue size: %d)" % [scene_id, _queue.size()])
		return true

	# 开始新转换
	_start_transition(scene_id)
	return true


## 获取当前进度
func get_progress() -> int:
	return _current_progress


## 是否正在转换中
func is_transitioning() -> bool:
	return _is_transitioning


## 注入依赖（三参数版本，匹配测试 API）
func set_dependencies(
	transition_manager: Object = null,
	scene_system: Node = null,
	scene_loader: Object = null
) -> void:
	_transition_manager = transition_manager
	_scene_system = scene_system
	_scene_loader = scene_loader


## 设置 InputManager（单独设置，匹配测试 API）
func set_input_manager(input_mgr: Node) -> void:
	_input_manager = input_mgr


## 获取当前场景ID
func get_current_scene_id() -> String:
	return _current_scene_id


## 获取当前转换状态
func get_current_state() -> TransitionState:
	return _state


## 获取转换持续时间（毫秒）
func get_transition_duration() -> int:
	if _transition_start_time == 0:
		return 0
	return Time.get_ticks_msec() - _transition_start_time


## 取消当前转换
func cancel_transition() -> void:
	if _is_transitioning:
		_is_transitioning = false
		_state = TransitionState.IDLE
		_unblock_input()
		_queue.clear()
		_pending_scene_id = ""


## 设置当前场景ID（由 SceneManagementSystem 调用）
func set_current_scene_id(scene_id: String) -> void:
	_current_scene_id = scene_id


## 获取队列大小
func get_queue_size() -> int:
	return _queue.size()


# ── Transition Flow ────────────────────────────────────────────────────────

## 开始完整的场景转换流程
func _start_transition(scene_id: String) -> void:
	if _is_transitioning:
		push_warning("SceneTransition: Already transitioning, queueing: %s" % scene_id)
		_queue.append(scene_id)
		return

	_is_transitioning = true
	_transition_start_time = Time.get_ticks_msec()
	_last_progress_time = _transition_start_time
	_current_progress = 0
	_completed_phases.clear()
	_error_code = TransitionError.NONE

	# 通知转换开始
	var from_scene := _current_scene_id
	transition_started.emit(from_scene, scene_id)

	# Block input
	_block_input()

	# Emit initial progress (0%)
	_current_progress = 0
	transition_progress_changed.emit(0)
	_last_progress_time = _transition_start_time

	# Execute transition flow
	await _execute_transition(scene_id)


## 执行完整的转换流程
func _execute_transition(scene_id: String) -> void:
	_state = TransitionState.EXITING

	# Phase 1: Exit current scene
	if not _current_scene_id.is_empty() and _scene_system and _scene_system.has_method("exit_scene"):
		# Check timeout before the call
		if _check_timeout():
			transition_timeout_reached.emit(scene_id)
			_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out before exit")
			return
		await _scene_system.call("exit_scene")
		# Check timeout after the call completes
		if _check_timeout():
			transition_timeout_reached.emit(scene_id)
			_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out during exit")
			return
		_completed_phases.append("exiting")
		_update_progress_for_phase("fading_out", 0.0)

	# Check if still transitioning (might have been cancelled)
	if not _is_transitioning:
		return

	# Check timeout
	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after exiting")
		return

	# Phase 2: Fade out
	_state = TransitionState.FADING_OUT
	await _play_fade_out()
	_completed_phases.append("fading_out")
	_update_progress_for_phase("black_screen", 0.0)

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after fade out")
		return

	# Phase 3: Black screen
	_state = TransitionState.BLACK_SCREEN
	await _play_black_screen()
	_completed_phases.append("black_screen")
	_update_progress_for_phase("unloading", 0.0)

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after black screen")
		return

	# Phase 4: Unload current scene
	_state = TransitionState.UNLOADING
	if _scene_system and _scene_system.has_method("_unload_scene_resources"):
		await _scene_system.call("_unload_scene_resources")
		_completed_phases.append("unloading")
		_update_progress_for_phase("loading", 0.0)

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after unloading")
		return

	# Phase 5: Load new scene
	_state = TransitionState.LOADING
	if _scene_system and _scene_system.has_method("_load_scene_resources"):
		await _scene_system.call("_load_scene_resources", scene_id)

	# Also use SceneLoader if available
	if _scene_loader and _scene_loader.has_method("request_load"):
		_scene_loader.call("request_load", scene_id)
		# Wait for load completion with timeout
		await _wait_for_load_completion(scene_id)

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after loading")
		return

	_completed_phases.append("loading")
	_update_progress_for_phase("fading_in", 0.0)

	# Phase 6: Fade in
	_state = TransitionState.FADING_IN
	await _play_fade_in()
	_completed_phases.append("fading_in")
	_update_progress_for_phase("entering", 0.0)

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after fade in")
		return

	# Phase 7: Enter new scene
	_state = TransitionState.ENTERING
	if _scene_system and _scene_system.has_method("enter_scene"):
		var success = await _scene_system.call("enter_scene", scene_id)
		if success:
			_current_scene_id = scene_id

	if not _is_transitioning:
		return

	if _check_timeout():
		transition_timeout_reached.emit(scene_id)
		_fail_transition(scene_id, TransitionError.TIMEOUT, "Transition timed out after entering")
		return

	_completed_phases.append("entering")
	_update_progress_for_phase("entering", 1.0)

	# Complete transition
	_complete_transition(scene_id)


## 完成转换
func _complete_transition(scene_id: String) -> void:
	_state = TransitionState.COMPLETED
	_is_transitioning = false

	# Unblock input
	_unblock_input()

	_current_progress = 100
	transition_progress_changed.emit(100)

	transition_completed.emit(scene_id)

	# Reset state
	_state = TransitionState.IDLE

	# Process queue if any
	_process_queue()


## 转换失败
func _fail_transition(scene_id: String, error: TransitionError, reason: String) -> void:
	_error_code = error
	_is_transitioning = false
	_state = TransitionState.ERROR

	# Unblock input
	_unblock_input()

	transition_failed.emit(scene_id, reason)
	push_warning("SceneTransition: Failed - %s" % reason)

	# Reset to idle
	_state = TransitionState.IDLE
	_current_scene_id = ""


# ── Animation Phases ───────────────────────────────────────────────────────

func _play_fade_out() -> void:
	if _transition_manager and _transition_manager.has_method("play_fade_out"):
		await _transition_manager.call("play_fade_out")
	else:
		await get_tree().create_timer(FADE_OUT_DURATION).timeout


func _play_black_screen() -> void:
	if _transition_manager and _transition_manager.has_method("play_black_screen"):
		await _transition_manager.call("play_black_screen")
	else:
		await get_tree().create_timer(BLACK_SCREEN_DURATION).timeout


func _play_fade_in() -> void:
	if _transition_manager and _transition_manager.has_method("play_fade_in"):
		await _transition_manager.call("play_fade_in")
	else:
		# Fallback: simple timer
		await get_tree().create_timer(FADE_IN_DURATION).timeout


# ── Loading Completion ─────────────────────────────────────────────────────

func _wait_for_load_completion(scene_id: String) -> void:
	var start_time := Time.get_ticks_msec()

	while _is_transitioning:
		var elapsed := Time.get_ticks_msec() - start_time
		if elapsed > TRANSITION_TIMEOUT_MS:
			transition_timeout_reached.emit(scene_id)
			_fail_transition(scene_id, TransitionError.TIMEOUT, "Load timeout after %dms" % elapsed)
			return

		# Check if load is complete (if SceneLoader provides this info)
		if _scene_loader and _scene_loader.has_method("get_current_stage"):
			var stage = _scene_loader.call("get_current_stage")
			if stage == LOADING_COMPLETE_STAGE:  # LoadingStage.LOADED
				break

		await get_tree().process_frame


# ── Queue Management ───────────────────────────────────────────────────────

func _process_queue() -> void:
	if _queue.is_empty():
		return

	var next_scene: String = _queue.pop_front()
	if not next_scene.is_empty():
		_start_transition(next_scene)


# ── Input Blocking ─────────────────────────────────────────────────────────

func _block_input() -> void:
	if _input_manager and _input_manager.has_method("set_input_blocked"):
		_input_manager.call("set_input_blocked", true)


func _unblock_input() -> void:
	if _input_manager and _input_manager.has_method("set_input_blocked"):
		_input_manager.call("set_input_blocked", false)


# ── Progress Tracking ──────────────────────────────────────────────────────

func _calculate_progress(current_phase: String, phase_progress: float) -> float:
	var phase_weights = {
		"exiting": PHASE_WEIGHT_EXITING,
		"fading_out": PHASE_WEIGHT_FADING_OUT,
		"black_screen": PHASE_WEIGHT_BLACK_SCREEN,
		"unloading": PHASE_WEIGHT_UNLOADING,
		"loading": PHASE_WEIGHT_LOADING,
		"fading_in": PHASE_WEIGHT_FADING_IN,
		"entering": PHASE_WEIGHT_ENTERING
	}

	var completed_weight = 0.0
	for phase in _completed_phases:
		if phase_weights.has(phase):
			completed_weight += phase_weights[phase]

	var current_weight = phase_weights.get(current_phase, 0.0)
	return (completed_weight + current_weight * phase_progress) * 100.0


func _update_progress_for_phase(phase: String, phase_progress: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_progress_time < PROGRESS_UPDATE_INTERVAL_MS:
		return

	_current_progress = int(_calculate_progress(phase, phase_progress))
	_current_progress = clamp(_current_progress, 0, 100)
	transition_progress_changed.emit(_current_progress)
	_last_progress_time = now


func _check_timeout() -> bool:
	var elapsed := Time.get_ticks_msec() - _transition_start_time
	return elapsed > TRANSITION_TIMEOUT_MS
