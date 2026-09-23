extends GutTest

## 录制 TTS 回放模式（HybridAPI + AudioManager）的回归测试。
##
## 背景：为了让游戏在开发/演示时"按对话流程"稳定走完（不依赖实时 TTS 接口），
## scripts/record_dialogue_tts.py 把每条台词预录成
## `res://assets/test_audio/tts/<voice>_<lang>_<md5[:16]>.wav`，
## 客户端按 (voice, language, text) 查表播放。
##
## 这里锁住三件事：
## 1. 查表键算法与录制脚本一致（写死一条参照 md5，改算法必然失败）；
## 2. 真实台词能解析到真实文件（防"改了文案没重录"的静默漂移）；
## 3. 未命中时不会误播、且会被记账（便于补录），开关关闭时行为不变。

const REFERENCE_TEXT: String = "你醒啦。别怕，我叫腓腓。是我在混沌迷雾里发现了你，把你背回蜃影客栈的。"
const REFERENCE_KEY: String = "6f6f6d736b2546b6"


func test_recorded_tts_key_matches_python_recorder() -> void:
	# 与 scripts/record_dialogue_tts.py 的 record_key() 对齐：md5("<voice>|<lang>|<text>")[:16]
	assert_eq(
		HybridAPI._recorded_tts_key(REFERENCE_TEXT, "spirit", "zh"),
		REFERENCE_KEY,
		"查表键必须与录制脚本一致，否则所有台词都查不到录音"
	)


func test_recorded_tts_path_layout() -> void:
	var path := HybridAPI.recorded_tts_path(REFERENCE_TEXT, "spirit", "zh")
	assert_eq(
		path,
		"res://assets/test_audio/tts/spirit_zh_%s.wav" % REFERENCE_KEY,
		"录音路径必须是 <dir><voice>_<lang>_<key>.wav"
	)


func test_reference_line_has_a_recording_on_disk() -> void:
	var path := HybridAPI.recorded_tts_path(REFERENCE_TEXT, "spirit", "zh")
	assert_true(FileAccess.file_exists(path), "序章开场白应有录音：%s" % path)
	var stream := AudioManager.create_wav_stream_from_bytes(FileAccess.get_file_as_bytes(path))
	assert_not_null(stream, "录音应能解码成 AudioStreamWAV")
	if stream:
		assert_gt(stream.get_length(), 0.5, "录音时长应大于 0.5s（防静音占位文件混进来）")


func test_enabled_flag_roundtrip() -> void:
	var original := HybridAPI.recorded_tts_enabled
	HybridAPI.set_recorded_tts_enabled(true)
	assert_true(HybridAPI.recorded_tts_enabled, "开关应可打开")
	HybridAPI.set_recorded_tts_enabled(false)
	assert_false(HybridAPI.recorded_tts_enabled, "开关应可关闭")
	HybridAPI.recorded_tts_enabled = original


func test_miss_is_recorded_and_does_not_play() -> void:
	var original := HybridAPI.recorded_tts_enabled
	HybridAPI.set_recorded_tts_enabled(true)
	var missing_text := "这句台词故意没有录音-%s" % str(Time.get_ticks_usec())
	assert_false(
		HybridAPI._play_recorded_tts(missing_text, "spirit", "zh"),
		"未命中必须返回 false，让调用方回退实时 TTS"
	)
	var misses := HybridAPI.get_recorded_tts_misses()
	assert_true(
		misses.has(HybridAPI._recorded_tts_key(missing_text, "spirit", "zh")),
		"未命中的台词要记账，便于补录"
	)
	HybridAPI.recorded_tts_enabled = original


## 场景自带的 ASR 答案（见 MirageInnIntroductionController._configure_test_asr_audio）：
## 轮换位置必须能归零，否则从存档续进某个场景时，答案仍停在上一个场景的位置上
## —— 这正是"说要说出书架时一直不成功"的成因。
func test_asr_test_audio_index_can_reset() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_index: int = HybridAPI._asr_test_audio_index
	var original_files: Array[String] = HybridAPI.asr_test_audio_files.duplicate()

	HybridAPI.set_asr_default_answer_test_enabled(
		true, "res://test/fixtures/asr_test_audio/", ["02_second.wav", "10_first.wav"]
	)
	assert_eq(HybridAPI.asr_test_audio_files.size(), 2, "应装载两条测试音频")
	HybridAPI.get_next_asr_test_audio_data()
	HybridAPI.get_next_asr_test_audio_data()
	assert_eq(HybridAPI._asr_test_audio_index, 2, "取两轮后轮换位置应为 2")

	HybridAPI.reset_asr_test_audio_index()
	assert_eq(HybridAPI._asr_test_audio_index, 0, "归零后应从头开始取")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI._asr_test_audio_index = original_index
	HybridAPI.asr_test_audio_files = original_files
