extends GutTest

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

func test_asr_default_answer_test_removes_stale_postprocess() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_answers := HybridAPI.asr_default_test_answers.duplicate()
	var original_index := HybridAPI._asr_default_test_answer_index
	HybridAPI.set_asr_default_answer_test_enabled(true, ["hello"])

	var result := HybridAPI._apply_asr_default_answer_test({
		"text": "暑假",
		"postprocess": {
			"corrected_text": "书架",
			"extracted": {"answer": "书架"}
		}
	})

	assert_eq(result.get("text", ""), "hello", "测试覆盖应替换原始text")
	assert_false(result.has("postprocess"), "测试覆盖后不应保留旧postprocess纠错结果")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI.asr_default_test_answers = original_answers
	HybridAPI._asr_default_test_answer_index = original_index
