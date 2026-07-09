extends Node

const QUEST_WS_URL = "ws://localhost:8306/ws/quest"

# Signals emitted on WebSocket events
signal quest_completed(data: Dictionary)
signal badge_unlocked(data: Dictionary)
signal connection_changed(connected: bool)
signal connection_error(message: String)

var socket := WebSocketPeer.new()
var connected := false
var _user_id: String = "anonymous"

# --- reconnect ---
const MAX_RECONNECT_DELAY: float = 10.0
const MAX_RECONNECT_ATTEMPTS: int = 3
const CONNECT_TIMEOUT: float = 10.0
var reconnect_delay: float = 1.0
var reconnect_timer: float = 0.0
var reconnect_attempts: int = 0
var _wants_connection: bool = false
var _connecting_since: float = -1.0

# --- session state persistence ---
var _last_session_state: Dictionary = {}
var _pending_events: Array[Dictionary] = []

func connect_for_user(user_id: String = "anonymous") -> void:
	_user_id = user_id
	reconnect_delay = 1.0
	reconnect_timer = 0.0
	reconnect_attempts = 0
	_wants_connection = true
	_connecting_since = Time.get_ticks_msec() / 1000.0
	var url = QUEST_WS_URL + "?user_id=" + _user_id.uri_encode()
	var err = socket.connect_to_url(url)
	if err != OK:
		_connecting_since = -1.0
		connection_error.emit("Quest websocket connect failed: " + str(err))
	else:
		# Load saved session state on initial connect
		_load_session_state()

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

	# --- handle open/connected ---
	if state == WebSocketPeer.STATE_OPEN:
		socket.poll()
		if not connected:
			connected = true
			reconnect_delay = 1.0
			reconnect_attempts = 0
			connection_changed.emit(true)
			# Restore session state after reconnect
			_restore_session_after_reconnect()
		_connecting_since = -1.0
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet().get_string_from_utf8()
			var payload = JSON.parse_string(packet)
			if payload is Dictionary:
				_dispatch_event(payload)
		return

	# --- handle closed ---
	if state == WebSocketPeer.STATE_CLOSED:
		var was_connected = connected
		connected = false
		_connecting_since = -1.0
		if was_connected:
			connection_changed.emit(false)
		if not _wants_connection:
			return
		if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
			connection_error.emit("Quest reconnect exhausted after %d attempts" % MAX_RECONNECT_ATTEMPTS)
			_wants_connection = false
			return
		reconnect_timer += delta
		if reconnect_timer >= reconnect_delay:
			reconnect_timer = 0.0
			_connecting_since = Time.get_ticks_msec() / 1000.0
			var url = QUEST_WS_URL + "?user_id=" + _user_id.uri_encode()
			var err = socket.connect_to_url(url)
			if err != OK:
				_connecting_since = -1.0
				connection_error.emit("Quest reconnect attempt failed: " + str(err))
			reconnect_attempts += 1
			reconnect_delay = min(reconnect_delay * 2, MAX_RECONNECT_DELAY)
		return

	# --- connecting state: poll + timeout check ---
	socket.poll()
	if _connecting_since > 0 and (Time.get_ticks_msec() / 1000.0) - _connecting_since > CONNECT_TIMEOUT:
		push_warning("[QuestWS] Connection timeout after %.1fs, forcing close" % CONNECT_TIMEOUT)
		socket.close()

func _dispatch_event(payload: Dictionary) -> void:
	var event_type = payload.get("type", "")
	var data = payload.get("payload", {})

	match event_type:
		"quest_completed":
			quest_completed.emit(data)
			print("[QuestWS] quest_completed: ", data)
		"badge_unlocked":
			badge_unlocked.emit(data)
			print("[QuestWS] badge_unlocked: ", data)
		_:
			push_warning("[QuestWS] Unknown event type: ", event_type)

# --- session state persistence ---

func _save_session_state() -> void:
	"""Save current session state to UserPrefs for recovery after reconnect."""
	_last_session_state = {
		"user_id": _user_id,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var prefs = ConfigFile.new()
	var save_path = "user://quest_session_state.cfg"
	prefs.set_value("session", "state", JSON.stringify(_last_session_state))
	prefs.save(save_path)
	print("[QuestWS] Session state saved: ", _last_session_state)

func _load_session_state() -> void:
	"""Load previously saved session state."""
	var prefs = ConfigFile.new()
	var save_path = "user://quest_session_state.cfg"
	if prefs.load(save_path) == OK:
		var state_json = prefs.get_value("session", "state", "")
		if state_json != "":
			var loaded = JSON.parse_string(state_json)
			if loaded is Dictionary:
				_last_session_state = loaded
				print("[QuestWS] Session state loaded: ", _last_session_state)

func _restore_session_after_reconnect() -> void:
	"""Restore session state and flush pending events after reconnect."""
	if reconnect_attempts > 0:
		print("[QuestWS] Restoring session after reconnect (attempt %d)" % reconnect_attempts)
		# Send any pending events that were queued during disconnect
		for event in _pending_events:
			var json_str = JSON.stringify(event)
			socket.put_packet(json_str.to_utf8_buffer())
			print("[QuestWS] Flushed pending event: ", event.get("type", "unknown"))
		_pending_events.clear()
		# Reload session state from server by requesting current status
		_request_session_sync()

func _request_session_sync() -> void:
	"""Request current session state from server after reconnect."""
	# This would typically be an HTTP request to get current quest status
	# For now, we emit a signal that the game can listen to
	print("[QuestWS] Requesting session sync for user: ", _user_id)
