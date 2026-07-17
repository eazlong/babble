extends Node

const MAX_BUFFER_SIZE: int = 2646000  # ~30 seconds at 44100Hz stereo 16-bit
const MIN_VOICE_AUDIO: int = 40960  # ~500ms minimum real speech (~44100 * 2ch * 2byte * 0.5s)
const BLUETOOTH_INPUT_KEYWORDS: Array[String] = [
	"bluetooth",
	"airpods",
	"buds",
	"freebuds",
	"hands-free",
	"handsfree",
	"headset",
	"wireless",
	"beats",
	"bose",
	"jabra",
	"soundcore",
	"sony",
	"wh-",
	"wf-"
]
const MICROPHONE_INPUT_KEYWORDS: Array[String] = [
	"microphone",
	"mic",
	"built-in"
]

var is_recording: bool = false
var is_listening: bool = false
var audio_buffer: PackedByteArray = PackedByteArray()
var current_recording_envelope: Dictionary = {}
var current_recording_context: Dictionary = {}
var recording_started_at: float = 0.0
var max_recording_duration_by_attempt_type: Dictionary = {
	"default": 30.0,
	"repeat_sentence": 12.0,
	"short_answer": 10.0,
	"free_speech": 30.0,
}

var audio_capture: AudioEffectCapture
var mic_player: AudioStreamPlayer
var record_bus_idx: int = -1

var silence_threshold: float = 0.015
var silence_duration: float = 2.5
var min_speech_duration: float = 0.5  # seconds, ignore anything shorter
var last_voice_time: float = 0.0
var _voice_cooldown: float = 3.0  # seconds between voice detections
var _last_voice_ended_time: float = -999.0

# Debug
var _poll_count: int = 0
var _frame_count: int = 0
var _max_vol: float = 0.0
var _last_debug_time: float = 0.0
var _dumped_samples: bool = false

signal voice_started()
signal voice_ended(audio_data: PackedByteArray)
signal listening_started()
signal listening_stopped()

func _ready() -> void:
	record_bus_idx = AudioServer.get_bus_index("Record")
	if record_bus_idx == -1:
		AudioServer.add_bus()
		record_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(record_bus_idx, "Record")

	audio_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(record_bus_idx, audio_capture)

	# Mute Record bus output to prevent mic-to-speaker feedback loop.
	# AudioEffectCapture still receives data before the mute point.
	AudioServer.set_bus_mute(record_bus_idx, true)
	print("[VoicePipeline] _ready complete, Record bus idx=", record_bus_idx)

func start_listening(recording_context: Dictionary = {}) -> void:
	if is_listening:
		return
	_start_microphone()

	is_listening = true
	audio_buffer.clear()
	audio_capture.clear_buffer()
	current_recording_context = recording_context.duplicate(true)
	current_recording_envelope = _prepare_recording_envelope(recording_context)
	_recording_duck_begin()
	_poll_count = 0
	_frame_count = 0
	_max_vol = 0.0
	_dumped_samples = false
	_last_debug_time = Time.get_ticks_msec() / 1000.0
	listening_started.emit()
	print("[VoicePipeline] start_listening: threshold=", silence_threshold)

func stop_listening() -> void:
	if not is_listening:
		return
	print("[VoicePipeline] stop_listening: polls=", _poll_count, " frames=", _frame_count, " max_vol=", _max_vol, " buf=", audio_buffer.size())
	is_listening = false
	if is_recording and audio_buffer.size() > 0:
		is_recording = false
		var final_audio = audio_buffer.duplicate()
		audio_buffer.clear()
		print("[VoicePipeline] voice_ended on stop! audio_bytes=", final_audio.size())
		_complete_recording_attempt(final_audio, "speech_detected")
		voice_ended.emit(final_audio)
	else:
		is_recording = false
		_complete_recording_attempt(PackedByteArray(), "no_speech_detected")
		audio_buffer.clear()
	audio_capture.clear_buffer()
	listening_stopped.emit()
	_recording_duck_end()

	_stop_microphone()

func _start_microphone() -> void:
	if mic_player and mic_player.playing:
		return

	# Print all available input devices
	var input_devices = AudioServer.get_input_device_list()
	print("[VoicePipeline] Input devices (", input_devices.size(), "):")
	for i in range(input_devices.size()):
		print("  [", i, "] ", input_devices[i])

	if input_devices.is_empty():
		push_warning("[VoicePipeline] No audio input devices found!")
		return

	var selected_device = _select_preferred_input_device(input_devices)

	AudioServer.set_input_device(selected_device)
	print("[VoicePipeline] Selected input device: ", selected_device)

	var mic_stream = AudioStreamMicrophone.new()
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = mic_stream
	mic_player.bus = "Record"
	mic_player.name = "MicPlayer"
	add_child(mic_player)
	mic_player.play()

	print("[VoicePipeline] MicPlayer on bus=", mic_player.bus, " playing=", mic_player.playing)

func _select_preferred_input_device(input_devices: PackedStringArray) -> String:
	for device in input_devices:
		if _device_name_has_keyword(device, BLUETOOTH_INPUT_KEYWORDS):
			return device

	for device in input_devices:
		if _device_name_has_keyword(device, MICROPHONE_INPUT_KEYWORDS):
			return device

	return input_devices[0]

func _device_name_has_keyword(device_name: String, keywords: Array[String]) -> bool:
	var lower_name = device_name.to_lower()
	for keyword in keywords:
		if keyword in lower_name:
			return true
	return false

func _stop_microphone() -> void:
	if not mic_player:
		return

	mic_player.stop()
	mic_player.queue_free()
	mic_player = null
	print("[VoicePipeline] Microphone stream stopped")

func _process(delta: float) -> void:
	if not is_listening:
		return

	var frames_available = audio_capture.get_frames_available()
	_poll_count += 1

	if frames_available > 0:
		var frames = audio_capture.get_buffer(frames_available)

		if frames.size() > 0:
			_frame_count += 1

			# Dump first few raw samples for debugging
			if not _dumped_samples and _frame_count <= 3:
				_dumped_samples = true
				print("[VoicePipeline] Raw samples (first 10 frames):")
				for i in range(mini(10, frames.size())):
					print("  frame[", i, "] x=", frames[i].x, " y=", frames[i].y)

			var volume = calculate_volume(frames)
			if volume > _max_vol:
				_max_vol = volume

			if volume > silence_threshold:
				if not is_recording:
					var current_time = Time.get_ticks_msec() / 1000.0
					if current_time - _last_voice_ended_time < _voice_cooldown:
						pass  # In cooldown period, ignore this trigger
					else:
						is_recording = true
						recording_started_at = current_time
						print("[VoicePipeline] voice_started! volume=", volume)
						voice_started.emit()

				if is_recording:
					var current_time = Time.get_ticks_msec() / 1000.0
					last_voice_time = current_time
					var new_bytes = frames.to_byte_array()
					if audio_buffer.size() + new_bytes.size() <= MAX_BUFFER_SIZE:
						audio_buffer.append_array(new_bytes)
					if current_time - recording_started_at >= _max_recording_duration():
						_finalize_current_recording("max_duration_reached")

			elif is_recording:
				var current_time = Time.get_ticks_msec() / 1000.0
				if current_time - last_voice_time > silence_duration:
					_finalize_current_recording("speech_detected")

	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_debug_time >= 1.0:
		print("[VoicePipeline] polls=", _poll_count, " frames=", _frame_count,
			" available=", frames_available, " recording=", is_recording,
			" buf=", audio_buffer.size(), " max_vol=", _max_vol)
		_max_vol = 0.0
		_last_debug_time = now

func calculate_volume(frames: PackedVector2Array) -> float:
	var sum: float = 0.0
	for frame in frames:
		sum += abs(frame.x) + abs(frame.y)
	return sum / (frames.size() * 2.0)

func _finalize_current_recording(completion_reason: String) -> void:
	is_recording = false
	var final_audio = audio_buffer.duplicate()
	audio_buffer.clear()
	_last_voice_ended_time = Time.get_ticks_msec() / 1000.0

	if final_audio.size() < MIN_VOICE_AUDIO:
		print("[VoicePipeline] voice_ended ignored (too short: ", final_audio.size(), " bytes)")
		_complete_recording_attempt(PackedByteArray(), "no_speech_detected")
		return

	var duration_sec = float(final_audio.size()) / 352800.0  # 44100 * 8 bytes per frame
	print("[VoicePipeline] voice_ended! audio_bytes=", final_audio.size(), " duration=%.2fs" % duration_sec)
	_complete_recording_attempt(final_audio, completion_reason)
	voice_ended.emit(final_audio)

func _prepare_recording_envelope(recording_context: Dictionary) -> Dictionary:
	var magic_echo_manager := get_node_or_null("/root/MagicEchoManager")
	if magic_echo_manager == null or not magic_echo_manager.has_method("prepare_recording_attempt"):
		return {}
	var context := recording_context.duplicate(true)
	if str(context.get("child_id", "")).is_empty():
		context["child_id"] = _current_child_id()
	if str(context.get("game_session_id", "")).is_empty():
		var active: Variant = magic_echo_manager.call("get_active_session", context.get("child_id", ""))
		if active is Dictionary:
			context["game_session_id"] = active.get("game_session_id", "")
	if str(context.get("game_session_id", "")).is_empty() or str(context.get("prompt_turn_id", "")).is_empty():
		return {}
	var envelope: Variant = magic_echo_manager.call("prepare_recording_attempt", context)
	if envelope is Dictionary:
		return envelope.duplicate(true)
	return {}

func _complete_recording_attempt(audio_data: PackedByteArray, completion_reason: String) -> void:
	if current_recording_envelope.is_empty():
		return
	var magic_echo_manager := get_node_or_null("/root/MagicEchoManager")
	if magic_echo_manager == null or not magic_echo_manager.has_method("complete_recording_attempt"):
		return
	magic_echo_manager.call(
		"complete_recording_attempt",
		current_recording_envelope.get("local_recording_id", ""),
		audio_data,
		{"completion_reason": completion_reason}
	)
	current_recording_envelope = {}

func _current_child_id() -> String:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null:
		return "local-child"
	var player_name := str(game_manager.get("player_name"))
	if player_name.is_empty():
		return "local-child"
	return player_name

func _max_recording_duration() -> float:
	var attempt_type := str(current_recording_context.get("attempt_type", "default"))
	return float(max_recording_duration_by_attempt_type.get(attempt_type, max_recording_duration_by_attempt_type.get("default", 30.0)))

func _recording_duck_begin() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("begin_recording_duck"):
		audio_manager.call("begin_recording_duck")

func _recording_duck_end() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("end_recording_duck"):
		audio_manager.call("end_recording_duck")
