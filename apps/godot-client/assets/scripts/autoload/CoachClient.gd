extends Node

const COACH_WS_URL = "ws://localhost:8305/ws/coach"

signal intervention_received(payload: Dictionary)
signal connection_error(message: String)

var socket := WebSocketPeer.new()
var session_id: String = ""
var connected := false

# ——— reconnect ———
const MAX_RECONNECT_DELAY: float = 10.0
const MAX_RECONNECT_ATTEMPTS: int = 3
const CONNECT_TIMEOUT: float = 10.0
var reconnect_delay: float = 1.0
var reconnect_timer: float = 0.0
var reconnect_attempts: int = 0
var _wants_connection: bool = false
var _connecting_since: float = -1.0

# ——— session state ———
var _last_coach_state: Dictionary = {}
var _pending_interventions: Array[Dictionary] = []

func connect_for_session(next_session_id: String) -> void:
	session_id = next_session_id
	reconnect_delay = 1.0
	reconnect_timer = 0.0
	reconnect_attempts = 0
	_wants_connection = true
	_connecting_since = Time.get_ticks_msec() / 1000.0
	var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
	var err = socket.connect_to_url(url)
	if err != OK:
		_connecting_since = -1.0
		connection_error.emit("Coach websocket connect failed: " + str(err))
	else:
		_load_coach_state()

func disconnect_socket() -> void:
	_wants_connection = false
	reconnect_attempts = 0
	reconnect_timer = 0.0
	_connecting_since = -1.0
	if connected:
		socket.close()
	connected = false

func _process(delta: float) -> void:
	var state = socket.get_ready_state()

	# ——— handle open/connected ———
	if state == WebSocketPeer.STATE_OPEN:
		socket.poll()
		if not connected:
			connected = true
			# Restore coach state after reconnect
			_restore_coach_after_reconnect()
		_connecting_since = -1.0
		reconnect_delay = 1.0
		reconnect_timer = 0.0
		reconnect_attempts = 0
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet().get_string_from_utf8()
			var payload = JSON.parse_string(packet)
			if payload is Dictionary:
				_cache_coach_state(payload)
				intervention_received.emit(payload)
		return

	# ——— handle closed ———
	if state == WebSocketPeer.STATE_CLOSED:
		connected = false
		_connecting_since = -1.0
		if not _wants_connection:
			return
		if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
			connection_error.emit("Coach reconnect exhausted after %d attempts" % MAX_RECONNECT_ATTEMPTS)
			_wants_connection = false
			return
		reconnect_timer += delta
		if reconnect_timer >= reconnect_delay:
			reconnect_timer = 0.0
			_connecting_since = Time.get_ticks_msec() / 1000.0
			var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
			var err = socket.connect_to_url(url)
			if err != OK:
				_connecting_since = -1.0
				connection_error.emit("Coach reconnect attempt failed: " + str(err))
			reconnect_attempts += 1
			reconnect_delay = min(reconnect_delay * 2, MAX_RECONNECT_DELAY)
		return

	# ——— connecting state: poll + timeout check ———
	socket.poll()
	if _connecting_since > 0 and (Time.get_ticks_msec() / 1000.0) - _connecting_since > CONNECT_TIMEOUT:
		push_warning("[CoachClient] Connection timeout after %.1fs, forcing close" % CONNECT_TIMEOUT)
		socket.close()

# ——— session state management ———

func _save_coach_state() -> void:
	"""Save current coach state to user prefs."""
	_last_coach_state["saved_at"] = Time.get_unix_time_from_system()
	var prefs = ConfigFile.new()
	var save_path = "user://coach_session_state.cfg"
	prefs.set_value("session", "state", JSON.stringify(_last_coach_state))
	prefs.save(save_path)

func _load_coach_state() -> void:
	"""Load previously saved coach state."""
	var prefs = ConfigFile.new()
	var save_path = "user://coach_session_state.cfg"
	if prefs.load(save_path) == OK:
		var state_json = prefs.get_value("session", "state", "")
		if state_json != "":
			var loaded = JSON.parse_string(state_json)
			if loaded is Dictionary:
				_last_coach_state = loaded

func _cache_coach_state(payload: Dictionary) -> void:
	"""Cache coach intervention state for potential recovery."""
	_last_coach_state["last_intervention"] = payload
	_last_coach_state["session_id"] = session_id
	_save_coach_state()

func _restore_coach_after_reconnect() -> void:
	"""Restore coach state and notify about reconnection."""
	if reconnect_attempts > 0:
		print("[CoachClient] Restored after reconnect (attempt %d)" % reconnect_attempts)
		# Emit a special signal to indicate reconnection with cached state
		var restore_payload = {
			"type": "session_restored",
			"session_id": session_id,
			"last_state": _last_coach_state,
			"reconnect_attempt": reconnect_attempts,
		}
		intervention_received.emit(restore_payload)
