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

func test_recognize_speech_uses_context_candidate_when_provided() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	HybridAPI.set_asr_default_answer_test_enabled(true)

	# MirageInnIntroduction 类型场景：candidate_answers 含 "书架"/"bookshelf"
	HybridAPI.recognize_speech(PackedByteArray([1, 2, 3]), "zh", {
		"candidate_answers": ["书架", "bookshelf", "book shelf"],
	})
	var result: Dictionary = await HybridAPI.asr_received

	assert_eq(result.get("text", ""), "书架", "上下文有candidate_answers时应优先取第一个")
	assert_eq(result.get("test_override", ""), "asr_default_answer_candidate", "应标记为候选人答案模式")

	# 没有 candidate_answers 时回退全局列表
	HybridAPI.recognize_speech(PackedByteArray([1, 2, 3]), "en", {})
	var result2: Dictionary = await HybridAPI.asr_received
	assert_eq(result2.get("test_override", ""), "asr_default_answer", "无candidate_answers时应回退全局列表")

	HybridAPI.asr_default_answer_test_enabled = original_enabled

func test_recognize_speech_emits_default_answer_without_http() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_answers := HybridAPI.asr_default_test_answers.duplicate()
	var original_index := HybridAPI._asr_default_test_answer_index
	HybridAPI.set_asr_default_answer_test_enabled(true, ["bookshelf"])

	HybridAPI.recognize_speech(PackedByteArray([1, 2, 3]), "zh", {"scene_id": "test_scene"})
	var result: Dictionary = await HybridAPI.asr_received

	assert_eq(result.get("text", ""), "bookshelf", "直接ASR测试模式应不依赖HTTP返回")
	assert_eq(result.get("detected_language", ""), "zh", "默认ASR结果应保留调用语言")
	assert_eq(result.get("context", {}).get("scene_id", ""), "test_scene", "默认ASR结果应保留调用上下文")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI.asr_default_test_answers = original_answers
	HybridAPI._asr_default_test_answer_index = original_index

func test_parallel_asr_returns_default_answer_without_http() -> void:
	var original_enabled := HybridAPI.asr_default_answer_test_enabled
	var original_answers := HybridAPI.asr_default_test_answers.duplicate()
	var original_index := HybridAPI._asr_default_test_answer_index
	HybridAPI.set_asr_default_answer_test_enabled(true, ["sunny"])

	var result: Dictionary = await HybridAPI.recognize_speech_parallel("abc123", 1500)

	assert_eq(result.get("text", ""), "sunny", "并行ASR测试模式应不依赖HTTP返回")
	assert_eq(result.get("detected_language", ""), "auto", "并行ASR默认结果应标记自动语言")
	assert_true(result.get("context", {}).get("parallel", false), "并行ASR默认结果应保留并行上下文")

	HybridAPI.asr_default_answer_test_enabled = original_enabled
	HybridAPI.asr_default_test_answers = original_answers
	HybridAPI._asr_default_test_answer_index = original_index
