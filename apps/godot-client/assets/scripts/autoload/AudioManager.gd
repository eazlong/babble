extends Node

var bgm_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var tts_player: AudioStreamPlayer

var bgm_volume: float = 0.8
var sfx_volume: float = 1.0
var tts_volume: float = 1.0

signal tts_finished()

func _ready() -> void:
	bgm_player = AudioStreamPlayer.new()
	sfx_player = AudioStreamPlayer.new()
	tts_player = AudioStreamPlayer.new()

	add_child(bgm_player)
	add_child(sfx_player)
	add_child(tts_player)

	bgm_player.volume_db = linear_to_db(bgm_volume)
	sfx_player.volume_db = linear_to_db(sfx_volume)
	tts_player.volume_db = linear_to_db(tts_volume)

	tts_player.finished.connect(_on_tts_finished)

func play_bgm(stream: AudioStream) -> void:
	if bgm_player.stream != stream:
		bgm_player.stream = stream
		bgm_player.play()

func stop_bgm() -> void:
	bgm_player.stop()

func play_sfx(stream: AudioStream) -> void:
	sfx_player.stream = stream
	sfx_player.play()

func play_tts(stream: AudioStream) -> void:
	tts_player.stream = stream
	tts_player.play()

func _on_tts_finished() -> void:
	tts_finished.emit()

func play_audio_from_base64(base64_data: String, format: String = "wav") -> void:
	var bytes = Marshalls.base64_to_raw(base64_data)
	if bytes.is_empty():
		push_error("Invalid base64 audio data")
		return

	var stream: AudioStream

	if format == "wav":
		stream = _create_wav_stream(bytes)
	elif format == "ogg":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)

	if stream:
		play_tts(stream)


func _create_wav_stream(wav_bytes: PackedByteArray) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()

	# Parse WAV header to extract format info and PCM offset
	var fmt: int = 0
	var mix_rate: int = 44100
	var stereo: bool = false
	var data_offset: int = 0

	# Read sample format (bytes 20-21)
	if wav_bytes.size() > 22:
		fmt = (wav_bytes[21] << 8) | wav_bytes[20]

	# Read channel count (bytes 22-23)
	if wav_bytes.size() > 24:
		var channels = (wav_bytes[23] << 8) | wav_bytes[22]
		stereo = channels == 2

	# Read sample rate (bytes 24-27)
	if wav_bytes.size() > 28:
		mix_rate = wav_bytes[24] | (wav_bytes[25] << 8) | (wav_bytes[26] << 16) | (wav_bytes[27] << 24)

	# Find "data" chunk offset
	var offset: int = 12
	while offset < wav_bytes.size() - 8:
		var chunk_id = wav_bytes.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size = wav_bytes[offset + 4] | (wav_bytes[offset + 5] << 8) | (wav_bytes[offset + 6] << 16) | (wav_bytes[offset + 7] << 24)
		if chunk_id == "data":
			data_offset = offset + 8
			break
		offset += 8 + chunk_size

	if data_offset == 0:
		# Fallback: assume standard 44-byte header
		data_offset = 44

	# Extract raw PCM data (skip WAV header)
	var pcm_data = wav_bytes.slice(data_offset)
	stream.data = pcm_data

	# Set format based on bits per sample
	match fmt:
		1:  # PCM 16-bit
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:  # Default to 16-bit
			stream.format = AudioStreamWAV.FORMAT_16_BITS

	stream.mix_rate = mix_rate
	stream.stereo = stereo

	return stream

func set_bgm_volume(volume: float) -> void:
	bgm_volume = volume
	bgm_player.volume_db = linear_to_db(volume)

func set_sfx_volume(volume: float) -> void:
	sfx_volume = volume
	sfx_player.volume_db = linear_to_db(volume)

func set_tts_volume(volume: float) -> void:
	tts_volume = volume
	tts_player.volume_db = linear_to_db(volume)
