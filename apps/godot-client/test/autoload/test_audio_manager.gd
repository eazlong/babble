extends GutTest

func test_has_newer_tts_playback_ignores_current_or_older_playback() -> void:
	var original_playback_id: int = AudioManager.tts_playback_id
	AudioManager.tts_playback_id = 10

	assert_false(AudioManager.has_newer_tts_playback(10), "当前播放 id 不应被当成本次等待后的新 TTS")
	assert_false(AudioManager.has_newer_tts_playback(11), "更旧的播放状态不应满足等待")
	assert_true(AudioManager.has_newer_tts_playback(9), "等待开始后新出现的 TTS 才能满足等待")

	AudioManager.tts_playback_id = original_playback_id

func test_tts_playback_finished_includes_current_playback_id() -> void:
	var original_playback_id: int = AudioManager.tts_playback_id
	var original_expected: bool = AudioManager._tts_expected
	var observed: Array = []
	var cb := func(playback_id: int, duration: float):
		observed.append(playback_id)
		observed.append(duration)

	AudioManager.tts_playback_finished.connect(cb)
	AudioManager.tts_playback_id = 42
	AudioManager._tts_expected = true
	AudioManager._on_tts_finished()
	AudioManager.tts_playback_finished.disconnect(cb)

	assert_eq(observed[0], 42, "完成信号应携带当前 TTS 播放 id")
	assert_eq(observed[1], 0.0, "无 stream 时 duration 应为 0")

	AudioManager.tts_playback_id = original_playback_id
	AudioManager._tts_expected = original_expected

func test_recording_duck_restores_previous_volumes() -> void:
	AudioManager.set_bgm_volume(0.8)
	AudioManager.set_sfx_volume(1.0)
	AudioManager.set_tts_volume(0.9)

	AudioManager.begin_recording_duck()
	assert_lt(AudioManager.bgm_volume, 0.8, "录音时BGM应降低")
	assert_lt(AudioManager.sfx_volume, 1.0, "录音时SFX应降低")
	assert_eq(AudioManager.tts_volume, 0.0, "录音时TTS应静音")

	AudioManager.end_recording_duck()
	assert_eq(AudioManager.bgm_volume, 0.8, "录音结束应恢复BGM")
	assert_eq(AudioManager.sfx_volume, 1.0, "录音结束应恢复SFX")
	assert_eq(AudioManager.tts_volume, 0.9, "录音结束应恢复TTS")

func test_recording_duck_is_idempotent() -> void:
	AudioManager.set_bgm_volume(0.6)
	AudioManager.set_sfx_volume(0.7)
	AudioManager.set_tts_volume(0.8)

	AudioManager.begin_recording_duck()
	var ducked_bgm := AudioManager.bgm_volume
	AudioManager.begin_recording_duck()
	assert_eq(AudioManager.bgm_volume, ducked_bgm, "重复duck不应继续叠加降音量")

	AudioManager.end_recording_duck()
	assert_eq(AudioManager.bgm_volume, ducked_bgm, "仍有嵌套duck时不应恢复")
	AudioManager.end_recording_duck()
	assert_eq(AudioManager.bgm_volume, 0.6, "最后一次结束后恢复原BGM")
	assert_eq(AudioManager.sfx_volume, 0.7, "最后一次结束后恢复原SFX")
	assert_eq(AudioManager.tts_volume, 0.8, "最后一次结束后恢复原TTS")

func test_extra_recording_duck_end_keeps_current_volumes() -> void:
	AudioManager.set_bgm_volume(0.5)
	AudioManager.set_sfx_volume(0.6)
	AudioManager.set_tts_volume(0.7)

	AudioManager.end_recording_duck()
	assert_eq(AudioManager.bgm_volume, 0.5, "多余end不应修改BGM")
	assert_eq(AudioManager.sfx_volume, 0.6, "多余end不应修改SFX")
	assert_eq(AudioManager.tts_volume, 0.7, "多余end不应修改TTS")
