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
