class_name SceneStateMachine
extends RefCounted

## 6-state scene lifecycle state machine.
## Manages transitions between: UNINITIALIZED, IDLE, TRANSITIONING_IN,
## ACTIVE, TRANSITIONING_OUT, ERROR.
##
## Signals:
##   state_changed(old_state: SceneState, new_state: SceneState)

enum State {
	UNINITIALIZED,
	IDLE,
	TRANSITIONING_IN,
	ACTIVE,
	TRANSITIONING_OUT,
	ERROR
}

signal state_changed(old_state: State, new_state: State)

var _current_state: State = State.UNINITIALIZED


## Returns the current state of the machine.
func get_current_state() -> State:
	return _current_state


## Attempt to transition to a new state.
## Returns true if the transition was valid and executed.
## Returns false if the transition was invalid — logs a warning.
func try_transition_to(new_state: State) -> bool:
	if not _can_transition_to(new_state):
		push_warning(
			"SceneStateMachine: Invalid transition from %s to %s"
			% [State.keys()[_current_state], State.keys()[new_state]]
		)
		return false

	var old_state := _current_state
	_current_state = new_state
	state_changed.emit(old_state, new_state)
	return true


## Recover from ERROR state back to IDLE.
## Only valid when currently in ERROR state.
func recover_to_idle() -> bool:
	return try_transition_to(State.IDLE)


## Initialize the state machine, transitioning from UNINITIALIZED to IDLE.
func initialize() -> bool:
	return try_transition_to(State.IDLE)


# ── Internal ──────────────────────────────────────────────────────────────


func _can_transition_to(new_state: State) -> bool:
	match _current_state:
		State.UNINITIALIZED:
			return new_state == State.IDLE
		State.IDLE:
			return new_state in [State.TRANSITIONING_IN, State.ERROR]
		State.TRANSITIONING_IN:
			return new_state in [State.ACTIVE, State.ERROR]
		State.ACTIVE:
			return new_state in [State.TRANSITIONING_OUT, State.ERROR]
		State.TRANSITIONING_OUT:
			return new_state in [State.IDLE, State.ERROR]
		State.ERROR:
			return new_state == State.IDLE
	return false
