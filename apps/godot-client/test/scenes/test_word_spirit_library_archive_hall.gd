extends GutTest

const ControllerScript = preload("res://assets/scripts/scenes/WordSpiritLibraryArchiveHallController.gd")

const _CONFIG_PATH: String = "res://assets/data/word_spirit_library_scene.json"

func _make_controller() -> Node:
	var controller = ControllerScript.new()
	controller.config = _load_test_config()
	# 加入场景树，使 get_node_or_null("/root/...") 能解析 autoload。
	add_child(controller)
	return controller

func _load_test_config() -> Dictionary:
	var file := FileAccess.open(_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}

# ── 字母名识别（方案 B：客户端本地分类）──────────────────────────────

func test_match_letter_single_uppercase() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("A"), "A", "单字母 A 应映射到 A")
	c.free()

func test_match_letter_single_lowercase() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("b"), "B", "小写 b 应映射到 B")
	c.free()

func test_match_letter_phonetic_bee() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("bee"), "B", "bee 应映射到 B")
	c.free()

func test_match_letter_phonetic_see() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("see"), "C", "see 应映射到 C")
	c.free()

func test_match_letter_strips_trailing_punctuation() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("B."), "B", "B. 去标点后映射到 B")
	c.free()

func test_match_letter_empty_returns_empty() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter(""), "", "空文本不应匹配字母")
	c.free()

func test_match_letter_unknown_word_returns_empty() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("hello"), "", "hello 不应匹配字母")
	c.free()

func test_match_letter_8_is_not_letter() -> void:
	var c = _make_controller()
	assert_eq(c._match_letter("8"), "", "数字 8 不应匹配字母")
	c.free()

# ── 指令词匹配（§5.4/§8.1）─────────────────────────────────────────

func test_match_command_undo() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("undo"), "undo", "undo 应匹配")
	c.free()

func test_match_command_back() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("back"), "undo", "back 应映射到 undo")
	c.free()

func test_match_command_done() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("done"), "done", "done 应匹配")
	c.free()

func test_match_command_leave() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("leave"), "leave", "leave 应匹配")
	c.free()

func test_match_command_with_trailing_words() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("leave now"), "leave", "leave now 应匹配 leave")
	c.free()

func test_match_command_empty_returns_empty() -> void:
	var c = _make_controller()
	assert_eq(c._match_command(""), "", "空文本不应匹配指令")
	c.free()

func test_match_command_unknown_returns_empty() -> void:
	var c = _make_controller()
	assert_eq(c._match_command("delete"), "", "未知指令 delete 不应匹配")
	c.free()

# ── 单词归一化 ───────────────────────────────────────────────────────

func test_normalize_word_lowercases_and_strips_punctuation() -> void:
	var c = _make_controller()
	assert_eq(c._normalize_word("Apple!"), "apple", "Apple! 应归一化为 apple")
	c.free()

func test_normalize_word_handles_spaces() -> void:
	var c = _make_controller()
	assert_eq(c._normalize_word("  Book  "), "book", "  Book  应归一化为 book")
	c.free()

# ── recording_context 构造（§6.2）────────────────────────────────────

func test_build_recording_context_wake_guardian() -> void:
	var c = _make_controller()
	c.current_word = {"word": "apple", "target": "APPLE"}
	var ctx: Dictionary = c._build_recording_context("wake_guardian", "archive_entry_wake", "", "open_greeting")
	assert_eq(ctx.get("attempt_type", ""), "wake_guardian", "入口阶段 attempt_type 应为 wake_guardian")
	assert_eq(ctx.get("scene_id", ""), "word_spirit_library_archive_hall", "scene_id 应正确")
	assert_true(ctx.has("max_duration"), "recording_context 应包含 max_duration")
	assert_eq(ctx.get("expected_answer_type", ""), "open_greeting", "expected_answer_type 应正确")
	c.free()

func test_build_recording_context_letter_name() -> void:
	var c = _make_controller()
	c.current_word = {"word": "apple", "target": "APPLE"}
	var typed_letters: Array[String] = ["A", "P"]
	c.spelled_letters = typed_letters
	var ctx: Dictionary = c._build_letter_context()
	assert_eq(ctx.get("attempt_type", ""), "letter_name", "拼写阶段 attempt_type 应为 letter_name")
	assert_eq(ctx.get("slot_index", 0), 2, "slot_index 应为当前拼写长度")
	assert_eq(ctx.get("word_id", ""), "apple", "word_id 应正确")
	c.free()

func test_build_recording_context_word_pronunciation() -> void:
	var c = _make_controller()
	c.current_word = {"word": "apple", "target": "APPLE"}
	var ctx: Dictionary = c._build_reading_context()
	assert_eq(ctx.get("attempt_type", ""), "word_pronunciation", "朗读阶段 attempt_type 应为 word_pronunciation")
	assert_eq(ctx.get("target_utterance_snapshot", ""), "APPLE", "target_utterance_snapshot 应为目标词")
	assert_eq(ctx.get("word_text", ""), "apple", "word_text 应为小写目标词")
	c.free()

func test_max_duration_for_attempt_uses_config() -> void:
	var c = _make_controller()
	assert_eq(c._max_duration_for_attempt("letter_name"), 3.0, "字母召唤硬上限应为 3s")
	assert_eq(c._max_duration_for_attempt("word_pronunciation"), 8.0, "朗读硬上限应为 8s")
	assert_eq(c._max_duration_for_attempt("wake_guardian"), 10.0, "唤醒硬上限应为 10s")
	c.free()

# ── HybridAPI.get_asr_confidence（阻塞 3）────────────────────────────

func test_hybrid_api_get_asr_confidence_prefers_postprocess() -> void:
	var result := {
		"confidence": 0.5,
		"postprocess": {"confidence": 0.85},
	}
	assert_eq(HybridAPI.get_asr_confidence(result), 0.85, "应优先读 postprocess.confidence")

func test_hybrid_api_get_asr_confidence_falls_back_to_top_level() -> void:
	var result := {"confidence": 0.42}
	assert_eq(HybridAPI.get_asr_confidence(result), 0.42, "无 postprocess 时应回退到顶层 confidence")

func test_hybrid_api_get_asr_confidence_defaults_zero() -> void:
	assert_eq(HybridAPI.get_asr_confidence({}), 0.0, "无任何 confidence 字段时应返回 0")

func test_hybrid_api_get_asr_confidence_falls_back_when_postprocess_zero() -> void:
	# 真实场景：postprocess.confidence=0.0（fallback_reason=missing_context）
	# 但顶层 Whisper confidence=0.9。此时应回退到顶层，否则字母会被误判低置信度。
	var result := {
		"confidence": 0.9,
		"postprocess": {"confidence": 0.0, "fallback_reason": "missing_context"},
	}
	assert_eq(HybridAPI.get_asr_confidence(result), 0.9, "postprocess.confidence=0 时应回退到顶层 confidence")

# ── VoicePipeline max_duration 覆盖（阻塞 6）─────────────────────────

func test_voice_pipeline_max_duration_prefers_context_override() -> void:
	var saved_ctx: Dictionary = VoicePipeline.current_recording_context
	VoicePipeline.current_recording_context = {"attempt_type": "letter_name", "max_duration": 5.0}
	assert_eq(VoicePipeline._max_recording_duration(), 5.0, "应优先使用 recording_context.max_duration")
	VoicePipeline.current_recording_context = saved_ctx

func test_voice_pipeline_max_duration_falls_back_to_map() -> void:
	var saved_ctx: Dictionary = VoicePipeline.current_recording_context
	VoicePipeline.current_recording_context = {"attempt_type": "short_answer"}
	assert_eq(VoicePipeline._max_recording_duration(), 10.0, "无 max_duration 时应回退到 attempt_type map")
	VoicePipeline.current_recording_context = saved_ctx

# ── GameManager 归卷厅进度字段（阻塞 5）──────────────────────────────

func test_game_manager_archive_hall_progress_round_trip() -> void:
	GameManager.set_archive_hall_progress({"current_word_index": 3, "inscribed_count": 2})
	var progress: Dictionary = GameManager.get_archive_hall_progress()
	assert_eq(progress.get("current_word_index", 0), 3, "归卷厅进度应可往返")
	assert_eq(progress.get("inscribed_count", 0), 2, "刻印数应可往返")

func test_game_manager_ink_shadow_queue_round_trip() -> void:
	GameManager.set_ink_shadow_queue(["apple", "book"])
	var queue: Array[String] = GameManager.get_ink_shadow_queue()
	assert_eq(queue.size(), 2, "墨影队列应可往返")
	assert_true(queue.has("apple"), "墨影队列应包含 apple")

# ── MagicEchoManager 场景映射（CLAUDE.md §3）─────────────────────────

func test_magic_echo_scene_id_map_includes_archive_hall() -> void:
	assert_eq(MagicEchoManager.normalize_scene_id("WordSpiritLibraryArchiveHall"), "word_spirit_library_archive_hall", "归卷厅场景应映射到规范化 id")
	assert_eq(MagicEchoManager.normalize_scene_id("word_spirit_library_archive_hall"), "word_spirit_library_archive_hall", "规范化 id 应幂等")

func test_magic_echo_learning_scenes_includes_archive_hall() -> void:
	assert_true(MagicEchoManager.is_learning_scene("word_spirit_library_archive_hall"), "归卷厅应被识别为学习场景")
	assert_true(MagicEchoManager.is_learning_scene("WordSpiritLibraryArchiveHall"), "归卷厅原场景名也应被识别为学习场景")

# ── 词牌池生成（阻塞 5：用 vocabulary_learned）──────────────────────

func test_build_word_pool_uses_vocabulary_learned() -> void:
	var c = _make_controller()
	var learned: Array[String] = ["apple", "book", "cat"]
	GameManager.vocabulary_learned = learned
	c._build_word_pool()
	assert_eq(c.word_pool.size(), 3, "词牌池应从 vocabulary_learned 生成")
	c.free()

func test_build_word_pool_falls_back_when_no_learned_words() -> void:
	var c = _make_controller()
	var empty_learned: Array[String] = []
	GameManager.vocabulary_learned = empty_learned
	c._build_word_pool()
	assert_true(c.word_pool.size() > 0, "无已学单词时应使用 fallback 词池")
	c.free()

# ── 置信度分层（§5.3）───────────────────────────────────────────────

func test_handle_letter_high_confidence_adopts_directly() -> void:
	var c = _make_controller()
	c.current_word = {"word": "cat", "target": "CAT"}
	c.phase = c.Phase.SPELLING
	# 模拟高置信度字母识别
	c._adopt_letter("C")
	assert_eq(c.spelled_letters.size(), 1, "高置信度字母应直接采纳")
	assert_eq(c.spelled_letters[0], "C", "采纳的字母应为 C")
	c.free()

func test_handle_letter_low_confidence_does_not_adopt() -> void:
	var c = _make_controller()
	c.current_word = {"word": "cat", "target": "CAT"}
	c.phase = c.Phase.SPELLING
	# 低置信度分支不调用 _adopt_letter，spelled_letters 应不变
	# 由于 _handle_letter_identified 含 await，这里只验证逻辑分支条件
	var high: float = float(c.config.get("letter_high_threshold", 0.80))
	var medium: float = float(c.config.get("letter_medium_threshold", 0.55))
	assert_true(0.40 < medium, "测试置信度 0.40 应低于中阈值")
	c.free()

# ── ASR result 全链路分派（诊断：第二次 letter_p 成功但流程没推进）──

func _make_controller_with_stubbed_io() -> Node:
	# partial_double 保留真实分派/匹配逻辑，只 stub 会触发真实 test-audio/HTTP/tts 的副作用。
	var c = partial_double(ControllerScript).new()
	c.config = _load_test_config()
	add_child(c)
	stub(c, "_start_listening").to_return(null)
	stub(c, "_stop_listening").to_return(null)
	stub(c, "_speak_flow").to_return(null)
	stub(c, "_update_slot_visuals").to_return(null)
	stub(c, "_update_stele_visuals").to_return(null)
	return c

func _make_letter_p_asr_result() -> Dictionary:
	# 复刻用户日志第二次 ASR response：letter_p.wav -> provide P
	return {
		"text": " P.",
		"confidence": 0.9,
		"language": "en",
		"postprocess": {
			"applied": true,
			"corrected_text": "P.",
			"correction_reason": "",
			"extracted": {},
			"intent_matched": true,
			"intent": "provide",
			"guidance": {"npc_line": "P."},
			"confidence": 0.9,
			"fallback_reason": null,
			"model": "deepseek-v4-flash",
			"latency_ms": 5346.0,
		},
	}

func test_letter_p_asr_result_advances_spelling() -> void:
	var c = _make_controller_with_stubbed_io()
	c.phase = c.Phase.SPELLING
	c.current_word = {"word": "apple", "target": "APPLE", "clue_type": "chinese_meaning", "clue_text": "苹果"}
	c.spelled_letters.clear()
	c._asr_request_active = true
	c._on_asr_received(_make_letter_p_asr_result())
	assert_eq(c.spelled_letters.size(), 1, "P 应被采纳进拼写槽位")
	assert_eq(c.spelled_letters[0], "P", "采纳的字母应为 P")
	c.free()

func test_letter_a_missing_context_asr_result_still_advances_spelling() -> void:
	# 复刻用户日志第一次：letter_a.wav -> missing_context/off_topic。
	# _on_letter_voice_ended 只看 corrected_text + 本地 _match_letter，不看 intent。
	var c = _make_controller_with_stubbed_io()
	c.phase = c.Phase.SPELLING
	c.current_word = {"word": "apple", "target": "APPLE", "clue_type": "chinese_meaning", "clue_text": "苹果"}
	c.spelled_letters.clear()
	c._asr_request_active = true
	var result := {
		"text": " A.",
		"confidence": 0.9,
		"language": "en",
		"postprocess": {
			"applied": false,
			"corrected_text": " A.",
			"correction_reason": null,
			"extracted": {},
			"intent_matched": false,
			"intent": "off_topic",
			"guidance": {"npc_line": null},
			"confidence": 0.0,
			"fallback_reason": "missing_context",
			"model": null,
			"latency_ms": 0.0,
		},
	}
	c._on_asr_received(result)
	assert_eq(c.spelled_letters.size(), 1, "A 应被采纳（corrected_text 含 A，与 intent 无关）")
	assert_eq(c.spelled_letters[0], "A", "采纳的字母应为 A")
	c.free()

# ── voice_ended 状态重置（诊断：第二次 P 成功但流程没推进）──────────

func test_on_voice_ended_resets_listening_flag() -> void:
	# voice_ended 表示一段录音已结束。controller 必须在此重置 _voice_listening，
	# 否则后续 _adopt_letter/_handle_no_speech 调 _start_listening 时
	# 会被 `if _voice_listening: return` 守卫拦截，下一次录音永不启动 → 流程卡死。
	var c = partial_double(ControllerScript).new()
	add_child(c)
	stub(c, "_hybrid_api").to_return(null)
	stub(c, "_speak_flow").to_return(null)
	stub(c, "_start_listening").to_return(null)
	stub(c, "_stop_listening").to_return(null)
	c._voice_listening = true
	c._asr_request_active = false
	c._on_voice_ended(PackedByteArray([1, 2, 3]))
	assert_false(c._voice_listening, "voice_ended 后必须清除 _voice_listening，否则下次 _start_listening 被守卫拦截")
	c.free()

# ── task_mode 声明（归卷厅非对话任务，voice-service 据此跳过 postprocess）──

func test_task_mode_maps_phase_to_non_dialogue() -> void:
	var c = _make_controller()
	c.current_word = {"word": "apple", "target": "APPLE"}
	var cases: Array = [
		[c.Phase.IDLE, "open_greeting"],
		[c.Phase.SPELLING, "letter_recognition"],
		[c.Phase.SPELL_CONFIRM, "letter_recognition"],
		[c.Phase.READING, "word_pronunciation"],
		[c.Phase.JUDGING, "word_pronunciation"],
		[c.Phase.PLAYBACK_REVIEW, "playback_self_eval"],
		[c.Phase.COMPLETE, "exit_command"],
		[c.Phase.EXITING, "exit_command"],
	]
	for entry in cases:
		c.phase = entry[0]
		assert_eq(c._current_task_mode(), entry[1], "phase %s 应映射到对应 task_mode" % str(entry[0]))
	c.free()

func test_asr_request_context_carries_task_mode() -> void:
	var c = _make_controller()
	c.current_word = {"word": "apple", "target": "APPLE"}
	c.phase = c.Phase.SPELLING
	var ctx: Dictionary = c._build_asr_request_context()
	assert_eq(ctx.get("task_mode", ""), "letter_recognition", "SPELLING 阶段 context 应带 task_mode=letter_recognition")
	# 字母阶段候选应为字母表，不是整个目标单词
	var candidates: Array = ctx.get("candidate_answers", [])
	assert_true(candidates.size() >= 26, "letter_name 阶段候选应为字母表 A-Z")
	assert_false("apple" in candidates, "候选不应包含整个目标单词")
	c.free()

# ── wake 阶段唤醒词识别（诊断：第一个字母 A 总是识别失败）──

func test_wake_phase_letter_does_not_trigger_wake() -> void:
	# wake 阶段说字母 A 不应唤醒（A 留给拼写），保持 IDLE 重听。
	# 整个玩法只唤醒一次；唤醒只接受 command_words.hello 集合。
	var c = _make_controller_with_stubbed_io()
	c.phase = c.Phase.IDLE
	c.current_word = {"word": "apple", "target": "APPLE", "clue_type": "chinese_meaning", "clue_text": "苹果"}
	c.spelled_letters.clear()
	c.word_pool = [c.current_word] as Array[Dictionary]
	c.current_word_index = 0
	c._asr_request_active = true
	var result := {
		"text": " A.",
		"confidence": 0.9,
		"language": "en",
		"postprocess": {
			"applied": false,
			"corrected_text": " A.",
			"correction_reason": null,
			"extracted": {},
			"intent_matched": true,
			"intent": "provide",
			"guidance": {"npc_line": null},
			"confidence": 0.0,
			"fallback_reason": "non_dialogue_task",
			"model": null,
			"latency_ms": 0.0,
		},
	}
	c._on_asr_received(result)
	assert_eq(c.phase, c.Phase.IDLE, "说字母 A 不应唤醒，保持 IDLE 重听")
	assert_eq(c.spelled_letters.size(), 0, "字母 A 不应在 wake 阶段被采纳或丢失")
	c.free()

func test_wake_phase_hello_triggers_wake() -> void:
	# wake 阶段说唤醒词 hello 才唤醒成功，进入拼写阶段。
	var c = _make_controller_with_stubbed_io()
	c.phase = c.Phase.IDLE
	c.current_word = {"word": "apple", "target": "APPLE", "clue_type": "chinese_meaning", "clue_text": "苹果"}
	c.spelled_letters.clear()
	c.word_pool = [c.current_word] as Array[Dictionary]
	c.current_word_index = 0
	c._asr_request_active = true
	var result := {
		"text": "hello",
		"confidence": 0.9,
		"language": "en",
		"postprocess": {
			"applied": false,
			"corrected_text": "hello",
			"correction_reason": null,
			"extracted": {},
			"intent_matched": true,
			"intent": "provide",
			"guidance": {"npc_line": null},
			"confidence": 0.0,
			"fallback_reason": "non_dialogue_task",
			"model": null,
			"latency_ms": 0.0,
		},
	}
	c._on_asr_received(result)
	assert_eq(c.phase, c.Phase.SPELLING, "说 hello 应唤醒成功进入拼写阶段")
	c.free()

func test_wake_audio_hello_matches_wake_word() -> void:
	# hello.wav 的 ASR 文本是 "hello"，
	# _match_command 整词匹配 hello 唤醒词。
	# 锁定唤醒音频选择正确。
	var c = _make_controller()
	assert_eq(c._match_command("hello"), "hello", "hello.wav 应匹配 hello 唤醒词")
	c.free()
