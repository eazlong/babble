extends GutTest

const TEST_AUDIO_DIR := "res://test/fixtures/asr_test_audio/"

func test_build_asr_request_body_includes_context() -> void:
	var context := {
		"npc_question": "这个家具是什么？",
		"expected_slots": [{"key": "answer", "type": "string"}],
		"expected_answer_type": "object_name",
		"candidate_answers": ["书架", "椅子"]
	}
	var body := HybridAPI._build_asr_request_body(PackedByteArray([1, 2, 3]), "cn_en", context)
	var parsed = JSON.parse_string(body)

	assert_eq(parsed.get("lang", ""), "cn_en", "ASR语言应进入请求体")
	assert_eq(parsed.get("audio_data", ""), Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])), "音频应按base64进入请求体")
	assert_eq(parsed.get("context", {}), context, "上下文应随ASR请求传给voice-service")

func test_build_asr_request_body_omits_empty_context() -> void:
	var body := HybridAPI._build_asr_request_body(PackedByteArray([1, 2, 3]), "en")
	var parsed = JSON.parse_string(body)

	assert_false(parsed.has("context"), "没有上下文时不应发送空context")

func test_get_asr_corrected_text_prefers_postprocess_text() -> void:
	var result := {
		"text": "暑假",
		"postprocess": {
			"corrected_text": "书架",
			"extracted": {"answer": "书架"}
		}
	}

	assert_eq(HybridAPI.get_asr_corrected_text(result), "书架", "应优先使用LLM纠错后的文本")

func test_get_asr_corrected_text_falls_back_to_raw_text() -> void:
	var result := {"text": "暑假"}

	assert_eq(HybridAPI.get_asr_corrected_text(result), "暑假", "缺少postprocess时应回退原始ASR文本")

func test_get_asr_extracted_value_prefers_slot_value() -> void:
	var result := {
		"text": "我叫大飞，大小的大，飞行的飞",
		"postprocess": {
			"corrected_text": "我叫大飞，大小的大，飞行的飞",
			"extracted": {"name": "大飞"}
		}
	}

	assert_eq(HybridAPI.get_asr_extracted_value(result, "name", ""), "大飞", "姓名流程应优先使用extracted.name")

func test_get_asr_intent_reads_enum_value() -> void:
	var result := {
		"postprocess": {
			"intent": "delegate",
			"intent_matched": false,
		}
	}

	assert_eq(HybridAPI.get_asr_intent(result), "delegate", "应优先读取postprocess.intent枚举")

func test_get_asr_intent_maps_legacy_intent_matched() -> void:
	assert_eq(HybridAPI.get_asr_intent({"postprocess": {"intent_matched": true}}), "provide", "旧intent_matched=true应映射为provide")
	assert_eq(HybridAPI.get_asr_intent({"postprocess": {"intent_matched": false}}), "off_topic", "旧intent_matched=false应映射为off_topic")

func test_get_asr_intent_ignores_unknown_enum() -> void:
	var result := {
		"postprocess": {
			"intent": "unknown",
			"intent_matched": true,
		}
	}

	assert_eq(HybridAPI.get_asr_intent(result), "provide", "未知intent应回退到旧布尔字段")

func test_get_asr_intent_defaults_to_provide_without_postprocess() -> void:
	assert_eq(HybridAPI.get_asr_intent({"text": "hello"}), "provide", "缺少postprocess时应保持旧流程默认通过")

func test_get_asr_intent_matched_reads_postprocess_value() -> void:
	var result := {
		"postprocess": {
			"intent_matched": false,
			"guidance": {"npc_line": "你可以告诉我你的名字。"}
		}
	}

	assert_false(HybridAPI.get_asr_intent_matched(result, true), "应读取LLM意图未达成结果")

func test_get_asr_intent_matched_falls_back_when_missing() -> void:
	assert_true(HybridAPI.get_asr_intent_matched({"text": "hello"}, true), "缺少postprocess时应默认不阻断剧情")

func test_get_asr_guidance_npc_line_reads_guidance() -> void:
	var result := {
		"postprocess": {
			"guidance": {"npc_line": "你可以告诉我你的名字。"}
		}
	}

	assert_eq(HybridAPI.get_asr_guidance_npc_line(result), "你可以告诉我你的名字。", "应读取LLM引导语")

func test_get_asr_guidance_npc_line_falls_back_when_missing() -> void:
	assert_eq(HybridAPI.get_asr_guidance_npc_line({"text": "hello"}, "fallback"), "fallback", "缺少引导语时应使用fallback")

func test_collect_asr_test_audio_files_lists_sorted_wavs() -> void:
	var files := HybridAPI._collect_asr_test_audio_files(TEST_AUDIO_DIR, [])

	assert_eq(files.size(), 2, "应扫描出两个wav文件")
	assert_true(files[0].ends_with("/02_second.wav"), "应按文件名升序排列")
	assert_true(files[1].ends_with("/10_first.wav"), "文件名排序而非字典序前缀")

func test_collect_asr_test_audio_files_filters_by_names_in_order() -> void:
	# 指定文件名列表时，只取这些文件并按列表顺序返回（与文件名字典序相反）。
	var files := HybridAPI._collect_asr_test_audio_files(TEST_AUDIO_DIR, ["10_first.wav", "02_second.wav"])

	assert_eq(files.size(), 2, "应只取指定的两个文件")
	assert_true(files[0].ends_with("/10_first.wav"), "顺序应跟随列表而非文件名")
	assert_true(files[1].ends_with("/02_second.wav"), "顺序应跟随列表而非文件名")

func test_collect_asr_test_audio_files_allows_missing_wav_suffix() -> void:
	var files := HybridAPI._collect_asr_test_audio_files(TEST_AUDIO_DIR, ["10_first"])

	assert_eq(files.size(), 1, "省略.wav后缀应仍能匹配")
	assert_true(files[0].ends_with("/10_first.wav"), "应匹配到对应wav文件")

func test_collect_asr_test_audio_files_skips_unknown_names() -> void:
	var files := HybridAPI._collect_asr_test_audio_files(TEST_AUDIO_DIR, ["02_second.wav", "missing.wav"])

	assert_eq(files.size(), 1, "目录中不存在的文件名应被跳过")
	assert_true(files[0].ends_with("/02_second.wav"), "应保留存在的文件")

func test_get_next_asr_test_audio_data_rotates() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_files := HybridAPI.asr_test_audio_files.duplicate()
	var original_index := HybridAPI._asr_test_audio_index
	HybridAPI.set_asr_default_answer_test_enabled(true, TEST_AUDIO_DIR)

	var first := HybridAPI.get_next_asr_test_audio_data()
	var second := HybridAPI.get_next_asr_test_audio_data()
	var third := HybridAPI.get_next_asr_test_audio_data()

	assert_gt(first.size(), 0, "第一次应读到音频字节")
	assert_eq(second.size(), first.size(), "第二次应读到另一文件且大小相同")
	assert_eq(third.size(), first.size(), "第三次应轮换回第一个文件")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI.asr_test_audio_files = original_files
	HybridAPI._asr_test_audio_index = original_index

func test_get_next_asr_test_audio_data_empty_when_no_files() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_files := HybridAPI.asr_test_audio_files.duplicate()
	var original_index := HybridAPI._asr_test_audio_index
	HybridAPI.set_asr_default_answer_test_enabled(true, "res://nonexistent_dir_xyz/")

	var data := HybridAPI.get_next_asr_test_audio_data()

	assert_eq(data.size(), 0, "目录不存在时应返回空字节数组")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI.asr_test_audio_files = original_files
	HybridAPI._asr_test_audio_index = original_index

func test_recognize_speech_does_not_short_circuit_in_test_mode() -> void:
	# 测试模式下 recognize_speech 不应再短路返回带 test_override 的假文本。
	# 旧实现必 emit 含 test_override 的结果；新实现走真实 HTTP，结果无此标记。
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	HybridAPI.set_asr_default_answer_test_enabled(true, TEST_AUDIO_DIR)

	# 临时屏蔽 api_error 的 push_error，避免真实 HTTP 失败被 GUT 计为 Unexpected Errors。
	var error_handler := HybridAPI.api_error.is_connected(HybridAPI._on_api_error)
	if error_handler:
		HybridAPI.api_error.disconnect(HybridAPI._on_api_error)

	var fake_override_seen := false
	var on_received := func(result: Dictionary) -> void:
		if result.has("test_override"):
			fake_override_seen = true
	HybridAPI.asr_received.connect(on_received)
	HybridAPI.recognize_speech(PackedByteArray([1, 2, 3]), "en", {})
	await get_tree().create_timer(0.3).timeout
	HybridAPI.asr_received.disconnect(on_received)

	if error_handler:
		HybridAPI.api_error.connect(HybridAPI._on_api_error)
	HybridAPI.asr_default_answer_test_enabled = original_enabled

	assert_false(fake_override_seen, "测试模式不应再短路 emit 带 test_override 的假结果")
