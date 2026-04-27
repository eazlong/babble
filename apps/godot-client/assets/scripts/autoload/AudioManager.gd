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
	var stream: AudioStream

	if format == "wav":
		stream = AudioStreamWAV.new()
		# Note: 需要根据实际音频格式设置参数
	elif format == "ogg":
		stream = AudioStreamOggVorbis.load_from_buffer(bytes)

	if stream:
		play_tts(stream)

func set_bgm_volume(volume: float) -> void:
	bgm_volume = volume
	bgm_player.volume_db = linear_to_db(volume)

func set_sfx_volume(volume: float) -> void:
	sfx_volume = volume
	sfx_player.volume_db = linear_to_db(volume)

func set_tts_volume(volume: float) -> void:
	tts_volume = volume
	tts_player.volume_db = linear_to_db(volume)