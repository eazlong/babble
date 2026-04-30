extends Node

const MAX_BUFFER_SIZE: int = 2646000  # ~30 seconds at 44100Hz stereo 16-bit

var is_recording: bool = false
var is_listening: bool = false
var audio_buffer: PackedByteArray = PackedByteArray()

var audio_capture: AudioEffectCapture
var mic_player: AudioStreamPlayer
var record_bus_idx: int = -1

var silence_threshold: float = 0.02
var silence_duration: float = 1.5
var last_voice_time: float = 0.0

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

func start_listening() -> void:
	_start_microphone()

	is_listening = true
	audio_buffer.clear()
	audio_capture.clear_buffer()
	listening_started.emit()

func stop_listening() -> void:
	is_listening = false
	is_recording = false
	audio_buffer.clear()
	audio_capture.clear_buffer()
	listening_stopped.emit()

	_stop_microphone()

func _start_microphone() -> void:
	if mic_player and mic_player.playing:
		return

	var input_devices = AudioServer.get_input_device_list()
	if input_devices.is_empty():
		push_warning("[VoicePipeline] No audio input devices found")
		return

	AudioServer.set_input_device(input_devices[0])
	print("[VoicePipeline] Using input device: ", input_devices[0])

	var mic_stream = AudioStreamMicrophone.new()
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = mic_stream
	mic_player.bus = "Record"
	mic_player.name = "MicPlayer"
	add_child(mic_player)
	mic_player.play()

	print("[VoicePipeline] Microphone stream started on Record bus")

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

	var frames = audio_capture.get_buffer(audio_capture.get_frames_available())

	if frames.size() > 0:
		var volume = calculate_volume(frames)

		if volume > silence_threshold:
			if not is_recording:
				is_recording = true
				voice_started.emit()

			last_voice_time = Time.get_ticks_msec() / 1000.0
			# Check buffer size limit before appending
			var new_bytes = frames.to_byte_array()
			if audio_buffer.size() + new_bytes.size() <= MAX_BUFFER_SIZE:
				audio_buffer.append_array(new_bytes)

		elif is_recording:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_voice_time > silence_duration:
				is_recording = false
				var final_audio = audio_buffer.duplicate()
				audio_buffer.clear()
				voice_ended.emit(final_audio)

func calculate_volume(frames: PackedVector2Array) -> float:
	var sum: float = 0.0
	for frame in frames:
		sum += abs(frame.x) + abs(frame.y)
	return sum / (frames.size() * 2.0)
