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
