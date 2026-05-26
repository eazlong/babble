extends Node

const COACH_WS_URL = "ws://localhost:8305/ws/coach"

signal intervention_received(payload: Dictionary)
signal connection_error(message: String)

var socket := WebSocketPeer.new()
var session_id: String = ""
var connected := false

# ——— reconnect ———
const MAX_RECONNECT_DELAY: float = 30.0
const MAX_RECONNECT_ATTEMPTS: int = 10
var reconnect_delay: float = 1.0
var reconnect_timer: float = 0.0
var reconnect_attempts: int = 0
var _wants_connection: bool = false

func connect_for_session(next_session_id: String) -> void:
	session_id = next_session_id
	reconnect_delay = 1.0
	reconnect_timer = 0.0
	reconnect_attempts = 0
	_wants_connection = true
	var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
	var err = socket.connect_to_url(url)
	if err != OK:
		connection_error.emit("Coach websocket connect failed: " + str(err))

func disconnect_socket() -> void:
	_wants_connection = false
	reconnect_attempts = 0
	reconnect_timer = 0.0
	if connected:
		socket.close()
	connected = false

func _process(delta: float) -> void:
	var state = socket.get_ready_state()

	# ——— handle open/connected ———
	if state == WebSocketPeer.STATE_OPEN:
		socket.poll()
		connected = true
		reconnect_delay = 1.0
		reconnect_timer = 0.0
		reconnect_attempts = 0
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet().get_string_from_utf8()
			var payload = JSON.parse_string(packet)
			if payload is Dictionary:
				intervention_received.emit(payload)
		return

	# ——— handle closed ———
	if state == WebSocketPeer.STATE_CLOSED:
		connected = false
		if not _wants_connection:
			return
		if reconnect_attempts >= MAX_RECONNECT_ATTEMPTS:
			connection_error.emit("Coach reconnect exhausted after %d attempts" % MAX_RECONNECT_ATTEMPTS)
			_wants_connection = false
			return
		reconnect_timer += delta
		if reconnect_timer >= reconnect_delay:
			reconnect_timer = 0.0
			var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
			var err = socket.connect_to_url(url)
			if err != OK:
				connection_error.emit("Coach reconnect attempt failed: " + str(err))
			reconnect_attempts += 1
			reconnect_delay = min(reconnect_delay * 2, MAX_RECONNECT_DELAY)
		return

	# ——— connecting state: poll ———
	socket.poll()
