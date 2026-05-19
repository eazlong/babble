extends Node

const COACH_WS_URL = "ws://localhost:8305/ws/coach"

signal intervention_received(payload: Dictionary)
signal connection_error(message: String)

var socket := WebSocketPeer.new()
var session_id: String = ""
var connected := false

func connect_for_session(next_session_id: String) -> void:
	session_id = next_session_id
	var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
	var err = socket.connect_to_url(url)
	if err != OK:
		connection_error.emit("Coach websocket connect failed: " + str(err))

func disconnect_socket() -> void:
	if connected:
		socket.close()
	connected = false

func _process(_delta: float) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		connected = false
		return

	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		connected = true

	while socket.get_available_packet_count() > 0:
		var packet = socket.get_packet().get_string_from_utf8()
		var payload = JSON.parse_string(packet)
		if payload is Dictionary:
			intervention_received.emit(payload)
