extends Node

const MAX_BUFFER_SIZE: int = 2646000  # ~30 seconds at 44100Hz stereo 16-bit
const MIN_VOICE_AUDIO: int = 40960  # ~500ms minimum real speech (~44100 * 2ch * 2byte * 0.5s)

var is_recording: bool = false
var is_listening: bool = false
var audio_buffer: PackedByteArray = PackedByteArray()

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

func start_listening() -> void:
	_start_microphone()

	is_listening = true
	audio_buffer.clear()
	audio_capture.clear_buffer()
	_poll_count = 0
	_frame_count = 0
	_max_vol = 0.0
	_dumped_samples = false
	_last_debug_time = Time.get_ticks_msec() / 1000.0
	listening_started.emit()
	print("[VoicePipeline] start_listening: threshold=", silence_threshold)

func stop_listening() -> void:
	print("[VoicePipeline] stop_listening: polls=", _poll_count, " frames=", _frame_count, " max_vol=", _max_vol, " buf=", audio_buffer.size())
	is_listening = false
	if is_recording and audio_buffer.size() > 0:
		is_recording = false
		var final_audio = audio_buffer.duplicate()
		audio_buffer.clear()
		print("[VoicePipeline] voice_ended on stop! audio_bytes=", final_audio.size())
		voice_ended.emit(final_audio)
	else:
		is_recording = false
		audio_buffer.clear()
	audio_capture.clear_buffer()
	listening_stopped.emit()

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

	# Try to find a non-default, non-aggregate device first
	var selected_device = input_devices[0]
	for device in input_devices:
		var lower = device.to_lower()
		if "microphone" in lower or "mic" in lower or "built-in" in lower:
			selected_device = device
			break

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
						print("[VoicePipeline] voice_started! volume=", volume)
						voice_started.emit()

				if is_recording:
					last_voice_time = Time.get_ticks_msec() / 1000.0
					var new_bytes = frames.to_byte_array()
					if audio_buffer.size() + new_bytes.size() <= MAX_BUFFER_SIZE:
						audio_buffer.append_array(new_bytes)

			elif is_recording:
				var current_time = Time.get_ticks_msec() / 1000.0
				if current_time - last_voice_time > silence_duration:
					is_recording = false
					var final_audio = audio_buffer.duplicate()
					audio_buffer.clear()
					_last_voice_ended_time = current_time

					# Suppress noise bursts that are too short to be real speech
					if final_audio.size() < MIN_VOICE_AUDIO:
						print("[VoicePipeline] voice_ended ignored (too short: ", final_audio.size(), " bytes)")
					else:
						var duration_sec = float(final_audio.size()) / 352800.0  # 44100 * 8 bytes per frame
						print("[VoicePipeline] voice_ended! audio_bytes=", final_audio.size(), " duration=%.2fs" % duration_sec)
						voice_ended.emit(final_audio)

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
