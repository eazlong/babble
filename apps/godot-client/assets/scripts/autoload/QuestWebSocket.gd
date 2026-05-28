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
const MAX_RECONNECT_DELAY: float = 30.0
const MAX_RECONNECT_ATTEMPTS: int = 10
const CONNECT_TIMEOUT: float = 10.0
var reconnect_delay: float = 1.0
var reconnect_timer: float = 0.0
var reconnect_attempts: int = 0
var _wants_connection: bool = false
var _connecting_since: float = -1.0

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
