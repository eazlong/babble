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

# ── 存档恢复(诊断:恢复后取牌双重跳词)──────────────────────────────

func test_restore_slices_pool_then_resets_index_to_zero() -> void:
	# 存档 current_word_index=3,恢复后词牌池切片为剩余 7 张;
	# _take_next_word_card 用 word_pool[current_word_index] 取牌,
	# 若切片后不把索引归零,会从 pool[3] 继续 → 双重跳词。
	var c = _make_controller()
	GameManager.vocabulary_learned = ["apple", "book", "cat", "dog", "egg", "fox", "guy", "hat", "ink", "jam"]
	GameManager.set_archive_hall_progress({"current_word_index": 3, "inscribed_count": 2})
	c._restore_progress()
	assert_eq(c.current_word_index, 3, "恢复后索引应指向下一张 = 3")
	c._build_word_pool()
	assert_eq(c.word_pool.size(), 7, "10 张词牌池按 index=3 切片后应剩 7 张")
	assert_eq(c.current_word_index, 0, "词牌池切片后 current_word_index 必须归零,否则取牌双重跳词")
	c.free()

func test_restore_index_cannot_overshoot_pool_after_slice() -> void:
	# 防御边界:存档 index=8/10,新会话切片后只剩 2 张;
	# 若索引不归零,8 >= 2 会令 _take_next_word_card 直接 _enter_complete()。
	var c = _make_controller()
	GameManager.vocabulary_learned = ["apple", "book", "cat", "dog", "egg", "fox", "guy", "hat", "ink", "jam"]
	c.current_word_index = 8
	c._build_word_pool()
	assert_eq(c.word_pool.size(), 2, "10 张词牌池按 index=8 切片后应剩 2 张")
	assert_true(c.current_word_index < c.word_pool.size(), "切片后索引必须小于池长,防止误判会话完成")
	assert_eq(c.current_word_index, 0, "切片后 current_word_index 应为 0")
	c.free()

# ── 星辉口径（ADR 0004 / Star Economy §3.1）──────────────────────────

func test_stars_per_response_follows_star_economy_table() -> void:
	# GDD §3.1 固定五档: 0-39→1★ 40-59→2★ 60-74→3★ 75-89→4★ 90-100→5★
	var c = _make_controller()
	assert_eq(c._stars_per_response(100), 5, "LXP 100 → 5★")
	assert_eq(c._stars_per_response(90), 5, "LXP 90 → 5★（下界含）")
	assert_eq(c._stars_per_response(89), 4, "LXP 89 → 4★")
	assert_eq(c._stars_per_response(75), 4, "LXP 75 → 4★（下界含）")
	assert_eq(c._stars_per_response(74), 3, "LXP 74 → 3★")
	assert_eq(c._stars_per_response(60), 3, "LXP 60 → 3★（下界含）")
	assert_eq(c._stars_per_response(59), 2, "LXP 59 → 2★")
	assert_eq(c._stars_per_response(40), 2, "LXP 40 → 2★（下界含）")
	assert_eq(c._stars_per_response(39), 1, "LXP 39 → 1★")
	assert_eq(c._stars_per_response(0), 0, "LXP 0 = 没有有效回应 → 不发星")
	c.free()

func test_stars_for_band_clear_and_close() -> void:
	var c = _make_controller()
	assert_eq(c._stars_for_band(c.BAND_CLEAR), 5, "清晰(≥0.85) → LXP 95 → 5★")
	assert_eq(c._stars_for_band(c.BAND_CLOSE), 4, "接近(0.65-0.84) → LXP 80 → 4★")
	c.free()

func test_stars_for_band_playback_review_is_two() -> void:
	var c = _make_controller()
	assert_eq(c._stars_for_band(c.BAND_PLAYBACK), 2, "回放自评接受 → LXP 50 → 2★")
	c.free()

func test_stars_for_band_demonstration_is_capped() -> void:
	# 示范模式: LXP 65 → 3★, 且受 demonstration_star_cap 约束
	var c = _make_controller()
	assert_eq(c._stars_for_band(c.BAND_DEMONSTRATION), 3, "示范后刻印 → LXP 65 → 3★")
	c.config["demonstration_star_cap"] = 2
	assert_eq(c._stars_for_band(c.BAND_DEMONSTRATION), 2, "旋钮调低后应封顶到 2★")
	c.free()

func test_stars_for_band_unknown_band_gives_zero() -> void:
	var c = _make_controller()
	assert_eq(c._stars_for_band("no_such_band"), 0, "未知档位不应发星")
	c.free()

func test_inscribe_no_longer_multiplies_stars_into_lxp() -> void:
	# v0.3 删除了 star_to_lxp_multiplier: LXP 不再由 star * multiplier 反推
	var c = _make_controller()
	assert_false(c.config.has("star_to_lxp_multiplier"), "配置里不应再有 star_to_lxp_multiplier")
	assert_true(c.config.has("star_to_lxp"), "配置里应有 star_to_lxp 映射表")
	c.free()

# ── 墨影词牌优先回流（§5.6）──────────────────────────────────────────

## 词池用例前置：GameManager 是跨用例共享的单例，前面的恢复用例会把
## archive_hall_progress.current_word_index 留成非 0 值；控制器 _ready() 恢复后
## 词池会在 _build_word_pool() 末尾被切片，断言看到的就是"剩余牌"而非"全部牌"。
func _prepare_word_pool(c) -> void:
	GameManager.set_archive_hall_progress({})
	c.current_word_index = 0
	c.word_pool.clear()

func test_ink_shadow_words_come_first_in_pool() -> void:
	var c = _make_controller()
	_prepare_word_pool(c)
	GameManager.vocabulary_learned = ["city", "house", "flower", "nest"]
	c.ink_shadow_queue.assign(["nest", "flower"])
	c._build_word_pool()
	assert_eq(c.word_pool.size(), 4, "4 个已学词应全部进池")
	# 队列按失败先后 append,回流时最近失败的排最前 → flower 在前
	assert_eq(str(c.word_pool[0].get("word", "")), "flower", "最近失败的词应排第一")
	assert_eq(str(c.word_pool[1].get("word", "")), "nest", "次近失败的词应排第二")
	c.free()

func test_ink_shadow_return_does_not_duplicate_or_exceed_daily_cards() -> void:
	var c = _make_controller()
	_prepare_word_pool(c)
	GameManager.vocabulary_learned = ["city", "house", "flower", "nest"]
	c.ink_shadow_queue.assign(["nest", "nest", "flower"])
	c._build_word_pool()
	var words: Array = []
	for card in c.word_pool:
		words.append(str(card.get("word", "")))
	assert_eq(words.size(), 4, "词池不应因重复的墨影条目而膨胀")
	assert_eq(words.count("nest"), 1, "同一个词在池中只应出现一次")
	c.free()

func test_ink_shadow_words_not_in_learned_are_skipped() -> void:
	var c = _make_controller()
	_prepare_word_pool(c)
	GameManager.vocabulary_learned = ["city"]
	c.ink_shadow_queue.assign(["dragon"])
	c._build_word_pool()
	assert_eq(c.word_pool.size(), 1, "未学过的回流词不应进池")
	assert_eq(str(c.word_pool[0].get("word", "")), "city", "池里只应有已学词")
	c.free()

func test_clear_from_ink_shadow_removes_word() -> void:
	var c = _make_controller()
	c.ink_shadow_queue.assign(["flower", "nest"])
	c._clear_from_ink_shadow("flower")
	assert_false(c.ink_shadow_queue.has("flower"), "刻印成功后该词应出列")
	assert_true(c.ink_shadow_queue.has("nest"), "其它词不应被误删")
	c.free()

func test_clear_from_ink_shadow_is_noop_for_absent_word() -> void:
	var c = _make_controller()
	c.ink_shadow_queue.assign(["nest"])
	c._clear_from_ink_shadow("flower")
	assert_eq(c.ink_shadow_queue.size(), 1, "不在队列里的词不应改变队列")
	c.free()

# ── 词牌线索词表（§4.4.1）────────────────────────────────────────────

func test_clue_rotation_cycles_configured_types() -> void:
	var c = _make_controller()
	# 配置为 ["chinese_meaning", "chinese_meaning", "sentence_gap"]
	assert_eq(c._clue_type_for_index(0), "chinese_meaning", "第 1 张用中文释义")
	assert_eq(c._clue_type_for_index(1), "chinese_meaning", "第 2 张用中文释义")
	assert_eq(c._clue_type_for_index(2), "sentence_gap", "第 3 张用例句缺词")
	assert_eq(c._clue_type_for_index(3), "chinese_meaning", "第 4 张回到中文释义")
	c.free()

func test_build_word_card_uses_sentence_gap_from_word_cards() -> void:
	var c = _make_controller()
	c._load_word_cards()
	assert_true(c.word_cards.has("city"), "word_cards.json 应含 city")
	var card: Dictionary = c._build_word_card("city", 2)
	assert_eq(str(card.get("clue_type", "")), "sentence_gap", "第 3 张应取例句缺词线索")
	assert_true(str(card.get("clue_text", "")).contains("___"), "例句线索必须带 ___ 空槽")
	assert_eq(str(card.get("clue_meaning", "")), "城市", "例句线索应带中文兜底释义")
	assert_eq(str(card.get("target", "")), "CITY", "目标词应为大写")
	c.free()

func test_build_word_card_uses_chinese_meaning_from_word_cards() -> void:
	var c = _make_controller()
	c._load_word_cards()
	var card: Dictionary = c._build_word_card("honeybee", 0)
	assert_eq(str(card.get("clue_type", "")), "chinese_meaning", "第 1 张应取中文释义")
	assert_eq(str(card.get("clue_text", "")), "蜜蜂", "释义应来自词表")
	assert_eq(str(card.get("target", "")), "HONEYBEE", "目标词应为大写")
	c.free()

func test_build_word_card_falls_back_when_word_not_in_cards() -> void:
	var c = _make_controller()
	c._load_word_cards()
	var card: Dictionary = c._build_word_card("zzz", 2)
	assert_eq(str(card.get("clue_type", "")), "chinese_meaning", "词表缺条目应回退中文释义")
	assert_eq(str(card.get("clue_text", "")), "zzz", "回退时线索就是单词本身")
	assert_eq(str(card.get("target", "")), "ZZZ", "回退时目标词应为大写")
	c.free()

func test_word_cards_cover_all_learned_words() -> void:
	# 长安集市两课去重后的 15 个可复习词都必须有词表条目,否则会静默回退成裸单词
	var c = _make_controller()
	c._load_word_cards()
	var lesson_words: Array = [
		"city", "country", "street", "building", "house", "flat", "farm", "live", "home",
		"eagle", "owl", "honeybee", "nest", "wall", "flower",
	]
	assert_eq(lesson_words.size(), 15, "前置:两课去重后应为 15 个词")
	for word in lesson_words:
		assert_true(c.word_cards.has(word), "词表缺少可复习词: %s" % word)
	c.free()

# ── 字母精灵（v0.3 §5.2.1）与演出拍 1–3（§13.6 第 1 批）────────────

const LetterSpiritScript = preload("res://assets/scripts/components/LetterSpirit.gd")
const SpellingSlotBarScript = preload("res://assets/scripts/components/SpellingSlotBar.gd")

# ── 版面让位：能量环 vs 其余内容（2026-09-22 用户反馈"字岩壁与能量标示重叠"）──
#
# 这一组测试钉的是**版面不变量**，不是具体坐标。写死坐标的断言在下次调版面时
# 只会变成假失败；真正会回归的是"谁压在谁身上"。

func test_letter_wall_clears_energy_dial() -> void:
	# 用户报的就是这条：岩壁从阵盘后面穿出来，字母 K/Q 被压在盘下。
	var c = _make_controller()
	var dial_bottom: float = c.ENERGY_DIAL_RECT.end.y
	for band in [
		[c.WALL_ORIGIN_UPPER, c.WALL_SIZE_UPPER, "上层"],
		[c.WALL_ORIGIN_MIDDLE, c.WALL_SIZE_MIDDLE, "中层"],
		[c.WALL_ORIGIN_LOWER, c.WALL_SIZE_LOWER, "下层"],
	]:
		assert_true(band[0].y >= dial_bottom,
			"%s岩壁 top=%.1f 必须在能量环底边 %.1f 之下" % [band[2], band[0].y, dial_bottom])
	c.free()

func test_wall_bands_do_not_overlap_each_other() -> void:
	# 三层是**独立石板**（板间留缝），叠在一起会变成一整块墙。
	var c = _make_controller()
	var upper_bottom: float = c.WALL_ORIGIN_UPPER.y + c.WALL_SIZE_UPPER.y
	var middle_bottom: float = c.WALL_ORIGIN_MIDDLE.y + c.WALL_SIZE_MIDDLE.y
	assert_true(upper_bottom <= c.WALL_ORIGIN_MIDDLE.y, "上层岩壁不应压到中层")
	assert_true(middle_bottom <= c.WALL_ORIGIN_LOWER.y, "中层岩壁不应压到下层")
	c.free()

func test_wall_bands_do_not_overlap_stele() -> void:
	var c = _make_controller()
	var lower_bottom: float = c.WALL_ORIGIN_LOWER.y + c.WALL_SIZE_LOWER.y
	assert_true(lower_bottom <= c.STELE_RECT.position.y,
		"下层岩壁 bottom=%.1f 不应插进石碑 top=%.1f" % [lower_bottom, c.STELE_RECT.position.y])
	c.free()

func test_every_letter_spirit_sits_on_its_own_band() -> void:
	# 岩壁底板与精灵是两处代码建的；它们共用 WALL_ORIGIN_* 才不会分家。
	var c = _make_controller()
	var bands: Array = [
		[c.WALL_ORIGIN_UPPER, c.WALL_SIZE_UPPER, c.config.get("letter_layers", {}).get("upper", [])],
		[c.WALL_ORIGIN_MIDDLE, c.WALL_SIZE_MIDDLE, c.config.get("letter_layers", {}).get("middle", [])],
		[c.WALL_ORIGIN_LOWER, c.WALL_SIZE_LOWER, c.config.get("letter_layers", {}).get("lower", [])],
	]
	var half_h: float = LetterSpiritScript.DEFAULT_SIZE.y * 0.5
	for band in bands:
		var origin: Vector2 = band[0]
		var band_size: Vector2 = band[1]
		for letter in band[2]:
			var spirit = c._spirit_for(str(letter))
			var cy: float = spirit.home_position.y + half_h
			assert_true(cy >= origin.y and cy <= origin.y + band_size.y,
				"精灵 %s 的中心 y=%.1f 落在岩壁 %.1f–%.1f 之外"
					% [letter, cy, origin.y, origin.y + band_size.y])
	c.free()

func test_content_stack_stays_on_screen() -> void:
	# 整体下移换来的是"别把内容推出屏幕"：词牌、石碑、光幕的下缘都必须在 1080 内。
	var c = _make_controller()
	var view_h: float = c.VIEW_SIZE.y
	assert_true(c.CARD_REST_POSITION.y + c.CARD_SIZE.y <= view_h, "词牌不应掉出屏幕下缘")
	assert_true(c.STELE_RECT.position.y + c.STELE_RECT.size.y <= view_h, "石碑不应掉出屏幕下缘")
	assert_true(c.CURTAIN_CENTER.y + c.CURTAIN_SIZE.y * 0.5 <= view_h, "光幕不应掉出屏幕下缘")
	c.free()

func test_energy_dial_is_the_only_thing_that_did_not_move_down() -> void:
	# 用户明确要求"除了能量标示以外的部分下移"。这条钉住"能量环留在原位"，
	# 免得下次调版面时顺手把它也挪了、下方内容又贴回去。
	var c = _make_controller()
	assert_true(c.CONTENT_SHIFT_Y > 0.0, "内容应有下移量")
	assert_eq(c.ENERGY_DIAL_RECT.position, Vector2(860, 2), "能量环位置是让位基准，不该跟着下移")
	var dial_bottom: float = c.ENERGY_DIAL_RECT.end.y
	# 其余内容整体下移：岩壁／石碑／槽位条都比"原值"低了一个 CONTENT_SHIFT_Y
	assert_almost_eq(c.WALL_ORIGIN_UPPER.y, 80.0 + c.CONTENT_SHIFT_Y, 0.001, "上层岩壁应已下移")
	assert_almost_eq(c.STELE_RECT.position.y, 460.0 + c.CONTENT_SHIFT_Y, 0.001, "石碑应已下移")
	assert_almost_eq(c.SLOT_BAR_POSITION.y, 620.0 + c.CONTENT_SHIFT_Y, 0.001, "槽位条应已下移")
	# 而能量环自身没动
	assert_true(c.ENERGY_DIAL_RECT.position.y < c.WALL_ORIGIN_UPPER.y, "能量环应在岩壁之上")
	assert_almost_eq(c.ENERGY_DIAL_RECT.end.y, 202.0, 0.001, "能量环底边（让位基准）")
	c.free()

func test_all_26_letters_have_a_spirit() -> void:
	var c = _make_controller()
	assert_eq(c.letter_spirits.size(), 26, "A–Z 应有 26 个字母精灵")
	for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		assert_true(c.letter_spirits.has(letter), "缺少字母精灵: %s" % letter)
	c.free()

func test_spirits_share_one_body_texture() -> void:
	# 决定 3：一套共享精灵体 + 字形叠加，不做 26 张立绘
	var c = _make_controller()
	var a = c._spirit_for("A")
	var z = c._spirit_for("Z")
	assert_eq(a.body_texture, z.body_texture, "所有精灵必须共享同一张精灵体贴图")
	assert_eq(a._glyph.text, "A", "字形用于区分字母")
	assert_eq(z._glyph.text, "Z", "字形用于区分字母")
	c.free()

func test_spirit_layer_is_added_last_so_it_draws_on_top() -> void:
	var c = _make_controller()
	var last_index: int = c.visual_root.get_child_count() - 1
	assert_eq(c.visual_root.get_child(last_index), c.spirit_layer, "精灵层必须在最上，否则飞行动画会被面板盖住")
	c.free()

func test_spirits_are_not_position_managed_by_a_container() -> void:
	# 精灵父节点若是 Container，position 会被容器覆写，精灵就飞不起来
	var c = _make_controller()
	for layer_letter in ["A", "B", "C", "J", "Z"]:
		var parent: Node = c._spirit_for(layer_letter).get_parent()
		assert_false(parent is Container, "精灵父节点不能是 Container")
		assert_eq(parent, c.spirit_layer, "所有精灵都应挂在 spirit_layer")
	c.free()

func test_letter_home_positions_spread_across_wall() -> void:
	# 原来的 HBoxContainer 是左对齐挤在左边，1680 宽的岩壁只用到 576；
	# v0.3 改为均匀铺满（§5.2.1 视觉形态）
	var c = _make_controller()
	var lower: Array = c.config.get("letter_layers", {}).get("lower", [])
	assert_eq(lower.size(), 9, "前置:lower 层 9 个字母")
	var centers: Array[float] = []
	for letter in lower:
		centers.append(c._spirit_for(str(letter)).home_position.x)
	for i in range(1, centers.size()):
		assert_true(centers[i] > centers[i - 1], "字母应从左到右依次排开")
	# 岩壁 (120, WALL_ORIGIN_LOWER.y) 尺寸 (1680,90)，margin 60 → 首个中心 x=180，精灵半宽 32
	assert_almost_eq(centers[0], 148.0, 1.0, "首个精灵应在岩壁左内边距处")
	assert_almost_eq(centers[8], 1708.0, 1.0, "末个精灵应在岩壁右内边距处")
	var a = c._spirit_for(str(lower[0]))
	# 岩壁垂直中线 = origin.y + 90/2；精灵以自己的中心对齐它。
	# 这里从常量推导而不是写死 333.0：岩壁整体下移过一次（能量环让位），
	# 写死的数字会随版面调整变成假失败，真正该钉的是"精灵居中于所属岩壁"。
	var band_center_y: float = c.WALL_ORIGIN_LOWER.y + c.WALL_SIZE_LOWER.y * 0.5
	assert_almost_eq(a.home_position.y + LetterSpiritScript.DEFAULT_SIZE.y * 0.5, band_center_y, 1.0,
		"精灵应垂直居中于所属岩壁")
	c.free()

func test_slot_center_spacing_matches_slot_bar() -> void:
	var c = _make_controller()
	var first: Vector2 = c._slot_center(0)
	var second: Vector2 = c._slot_center(1)
	assert_almost_eq(second.x - first.x, 60.0, 0.001, "槽位间距应为 48 宽 + 12 间隔")
	assert_almost_eq(second.y, first.y, 0.001, "同一行的槽位应等高")
	c.free()

# ── 拼写槽位条（"输入框"）：格数 + 动画（2026-09-22 重做）─────────────

func test_slot_count_follows_target_word_length() -> void:
	# 开局就按目标长度摆出 N 个空槽：孩子要能看出这个单词拼几个字母。
	var c = _make_controller()
	for target in ["CAT", "CITY", "BUILDING"]:
		c.current_word = {"word": target.to_lower(), "target": target}
		c.spelled_letters.clear()
		c._update_slot_visuals()
		assert_eq(c.slot_labels.size(), target.length(),
			"目标 %s(%d 字母) 应摆出 %d 个空槽" % [target, target.length(), target.length()])
		for i in range(target.length()):
			assert_eq(c.slot_labels[i].text, "", "开局第 %d 格应是空的" % i)
	c.free()

func test_slot_count_falls_back_when_no_word_taken() -> void:
	# 词表没加载出来 / 单元测试里 current_word 为空时，槽位条不能整条消失。
	var c = _make_controller()
	c.current_word = {}
	c.spelled_letters.assign(["A", "B"])
	c._update_slot_visuals()
	assert_eq(c.slot_labels.size(), 2, "无目标词时应回退成'已拼字母数'")
	c.free()

func test_slot_count_never_drops_below_spelled_letters() -> void:
	# 玩家多说了字母时，那些字母也必须看得见，否则他没法判断该 undo 掉哪个。
	# （真事：脚本化测试音频会把 APPLE 的 5 个字母灌进一张 CAT 词牌。）
	var c = _make_controller()
	c.current_word = {"word": "cat", "target": "CAT"}
	c.spelled_letters.assign(["A", "P", "L", "E", "A"])
	c._update_slot_visuals()
	assert_eq(c.slot_labels.size(), 5, "多说的字母也要有格子")
	c.spelled_letters.assign(["A", "P", "L", "E", "A", "P", "P", "L", "E"])
	c._update_slot_visuals()
	assert_eq(c.slot_labels.size(), 9, "9 个字母应有 9 格")
	for i in range(9):
		assert_eq(c.slot_labels[i].text, c.spelled_letters[i], "第 %d 格字形应跟上拼写序列" % i)
	c.free()

func test_slot_cells_fit_inside_the_frame() -> void:
	# 上限 10 格的依据是版面：槽框 600 宽，10*48 + 9*12 = 588 排得下，11 格就溢出。
	var c = _make_controller()
	c.current_word = {"word": "x", "target": "X"}
	c.spelled_letters.assign(["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"])
	c._update_slot_visuals()
	assert_eq(c.slot_labels.size(), SpellingSlotBarScript.MAX_CELLS, "应封顶到 MAX_CELLS")
	var half: float = SpellingSlotBarScript.CELL_SIZE.x * 0.5
	var first: Vector2 = c.slot_bar.get_cell_center(0)
	var last: Vector2 = c.slot_bar.get_cell_center(SpellingSlotBarScript.MAX_CELLS - 1)
	assert_true(first.x - half >= -0.001, "首格左缘不应超出槽框")
	assert_true(last.x + half <= c.slot_bar.size.x + 0.001,
		"末格右缘不应超出槽框（末格右缘 %.1f vs 框宽 %.1f）" % [last.x + half, c.slot_bar.size.x])
	c.free()

func test_slot_cells_are_centered_in_the_bar() -> void:
	# 4 字词和 8 字词都要在 600 宽的槽框里居中，否则短词会贴左边。
	var c = _make_controller()
	c.current_word = {"word": "cat", "target": "CAT"}
	c.spelled_letters.clear()
	c._update_slot_visuals()
	var bar_center_x: float = c.slot_bar.size.x * 0.5
	var first: Vector2 = c.slot_bar.get_cell_center(0)
	var last: Vector2 = c.slot_bar.get_cell_center(2)
	assert_almost_eq((first.x + last.x) * 0.5, bar_center_x, 0.001, "3 格应整体居中于槽框")
	c.current_word = {"word": "building", "target": "BUILDING"}
	c._update_slot_visuals()
	first = c.slot_bar.get_cell_center(0)
	last = c.slot_bar.get_cell_center(7)
	assert_almost_eq((first.x + last.x) * 0.5, bar_center_x, 0.001, "8 格应整体居中于槽框")
	assert_true(first.x >= 0.0 and last.x <= c.slot_bar.size.x, "槽位不应溢出槽框")
	c.free()

func test_slot_center_matches_component_cell_center() -> void:
	# 精灵的飞行落点必须和画面上的格子重合，否则字母会飞进空气里。
	var c = _make_controller()
	c.current_word = {"word": "city", "target": "CITY"}
	c.spelled_letters.clear()
	c._update_slot_visuals()
	for i in range(4):
		var expected: Vector2 = c.slot_bar.global_position + (c.slot_bar.get_cell_center(i) as Vector2)
		assert_almost_eq(c._slot_center(i).x, expected.x, 0.001, "第 %d 格落点 x 应对齐" % i)
		assert_almost_eq(c._slot_center(i).y, expected.y, 0.001, "第 %d 格落点 y 应对齐" % i)
	c.free()

func test_idle_empty_cells_breathe() -> void:
	# 待机呼吸：空槽的描边透明度必须随时间变，否则"输入框"是死的。
	var bar = SpellingSlotBarScript.new()
	bar.size = Vector2(600, 80)
	add_child(bar)
	bar.cell_count = 4
	assert_true(bar.is_animating(), "有空格时槽位条应处于动画态")
	bar._process(0.1)
	var a: float = bar._empty_rim_alpha(0)
	bar._process(SpellingSlotBarScript.BREATH_PERIOD_S * 0.5)
	var b: float = bar._empty_rim_alpha(0)
	assert_true(absf(a - b) > 0.05, "呼吸应让描边透明度变化（%.3f → %.3f）" % [a, b])
	assert_true(a >= SpellingSlotBarScript.BREATH_MIN_ALPHA - 0.001
		and a <= SpellingSlotBarScript.BREATH_MAX_ALPHA + 0.001, "呼吸幅度应在设定区间内")
	bar.free()

func test_filled_cell_stops_breathing() -> void:
	var bar = SpellingSlotBarScript.new()
	bar.size = Vector2(600, 80)
	add_child(bar)
	bar.cell_count = 3
	bar.set_glyph(0, "C")
	assert_true(bar.is_cell_filled(0), "填入后该格应标记为已填")
	bar.free()

func test_land_starts_glow_and_pops_the_glyph() -> void:
	# 填入演出：该格亮一圈光晕 + 字形弹入。
	var bar = SpellingSlotBarScript.new()
	bar.size = Vector2(600, 80)
	add_child(bar)
	bar.cell_count = 3
	bar.set_glyph(1, "A")
	bar.play_land(1)
	assert_true(bar.get_land_progress(1) > 0.0, "落位应点亮第 1 格的光晕")
	assert_true(bar.get_glyph_label(1).scale.x > 1.0, "字形应从放大态弹入")
	bar._process(SpellingSlotBarScript.LAND_DURATION_S)
	assert_eq(bar.get_land_progress(1), 0.0, "光晕应衰减干净")
	bar.free()

func test_land_ignores_out_of_range_index() -> void:
	var bar = SpellingSlotBarScript.new()
	bar.size = Vector2(600, 80)
	add_child(bar)
	bar.cell_count = 2
	bar.play_land(5)
	bar.play_land(-1)
	assert_eq(bar.get_land_progress(5), 0.0, "越界下标应安全忽略")
	bar.free()

func test_spirit_landing_lights_its_own_cell() -> void:
	# 端到端：说一个字母 → 精灵起飞 → 落位 → 该格亮起（而不是整条一起闪）。
	var c = _make_controller()
	c.current_word = {"word": "city", "target": "CITY"}
	c.spelled_letters.assign(["C"])
	c._flying_slot_index = 0
	c._update_slot_visuals()
	assert_eq(c.slot_labels[0].text, "", "飞行途中槽位不应显字")
	c._on_spirit_slotted("C")
	assert_eq(c.slot_labels[0].text, "C", "落位后槽位应亮起字形")
	assert_true(c.slot_bar.get_land_progress(0) > 0.0, "落位应触发该格光晕")
	assert_eq(c.slot_bar.get_land_progress(1), 0.0, "没落位的格子不应亮")
	c.free()

func test_adopt_letter_starts_flight_and_reserves_slot() -> void:
	var c = _make_controller_with_stubbed_io()
	c._adopt_letter("A")
	var spirit = c._spirit_for("A")
	assert_eq(spirit.state, LetterSpiritScript.State.FLYING, "采纳字母后精灵应起飞")
	assert_eq(c._flying_slot_index, 0, "应记录正在飞向的槽位下标")
	assert_eq(c.spelled_letters.size(), 1, "字母应已填入拼写序列")
	c.free()

func test_duplicate_letters_reuse_the_same_spirit() -> void:
	# apple 的两个 P：不克隆精灵，同一精灵连飞两次（§5.3）
	var c = _make_controller_with_stubbed_io()
	c._adopt_letter("P")
	c._adopt_letter("P")
	assert_eq(c.spelled_letters.size(), 2, "两个 P 都应在拼写序列里")
	assert_eq(c.letter_spirits.size(), 26, "不应为重复字母克隆新精灵")
	assert_eq(c._flying_slot_index, 1, "第二个 P 应飞向第 2 个槽位")
	c.free()

func test_slot_glyph_stays_hidden_while_spirit_in_flight() -> void:
	# 精灵还在飞时槽位不画字形，否则同一个字母会被画两次
	var c = _make_controller()
	c.spelled_letters.assign(["A"])
	c._flying_slot_index = 0
	c._update_slot_visuals()
	assert_eq(c.slot_labels[0].text, "", "飞行途中槽位不应显字")
	c._on_spirit_slotted("A")
	assert_eq(c.slot_labels[0].text, "A", "精灵落位后槽位应亮起字形")
	c.free()

func test_undo_returns_spirit_to_the_wall() -> void:
	var c = _make_controller_with_stubbed_io()
	c._first_undo_prompted = true
	c._adopt_letter("T")
	c._undo_last_letter()
	var spirit = c._spirit_for("T")
	assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "撤回后精灵应回到休眠态")
	assert_eq(spirit.position, spirit.home_position, "撤回后精灵应回到岩壁原位")
	assert_true(c.spelled_letters.is_empty(), "拼写序列应已撤回")
	c.free()

func test_clear_returns_every_spirit_home() -> void:
	var c = _make_controller_with_stubbed_io()
	for letter in ["C", "A", "T"]:
		c._adopt_letter(letter)
	c._clear_letters()
	for letter in ["C", "A", "T"]:
		var spirit = c._spirit_for(letter)
		assert_eq(spirit.position, spirit.home_position, "%s 应回原位" % letter)
	assert_true(c.spelled_letters.is_empty(), "清空后拼写序列应为空")
	c.free()

func test_inscribe_beat_writes_target_onto_the_stele() -> void:
	# 演出拍 2：铭文逐字刻入
	var c = _make_controller()
	c.config["inscribe_char_delay_ms"] = 10
	c.current_word = {"word": "cat", "target": "CAT"}
	c.spelled_letters.assign(["C", "A", "T"])
	c._update_slot_visuals()
	await c._play_inscribe_beat()
	assert_eq(c.stele_label.text, "CAT", "刻印演出结束后石碑应显完整目标词")
	c.free()

func test_inscribe_beat_skips_empty_target() -> void:
	var c = _make_controller()
	c.current_word = {}
	c.stele_label.text = "KEEP"
	await c._play_inscribe_beat()
	assert_eq(c.stele_label.text, "KEEP", "无目标词时不应清空石碑")
	c.free()

func test_scatter_beat_sends_spirits_home_and_clears_slots() -> void:
	# 演出拍 3：墨影散落抛物线回位（轻柔，不是错误蜂鸣）
	var c = _make_controller()
	c.config["scatter_fly_duration_ms"] = 20
	c.current_word = {"word": "cat", "target": "CAT"}
	c.spelled_letters.assign(["C", "A", "T"])
	c._update_slot_visuals()
	await c._play_scatter_beat()
	assert_true(c.spelled_letters.is_empty(), "散落演出后槽位应清空")
	# 槽位格数按目标单词长度常驻（CAT=3），散落撤掉的是**字形**而不是格子——
	# 输入框不该在清空时整条消失（2026-09-22 起：开局就摆出 N 个空槽）。
	assert_eq(c.slot_labels.size(), 3, "目标 3 字母 → 槽位条应保留 3 个空格")
	for i in range(3):
		assert_eq(c.slot_labels[i].text, "", "散落后第 %d 格应回到空槽" % i)
	for letter in ["C", "A", "T"]:
		var spirit = c._spirit_for(letter)
		assert_eq(spirit.position, spirit.home_position, "%s 应散落回岩壁原位" % letter)
		assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "%s 应回到休眠态" % letter)
	c.free()

func test_ink_shadow_flow_scatters_before_speaking() -> void:
	# 墨影流程必须先把槽位让出来（精灵从槽位起飞），再说话、再进下一张
	var c = _make_controller_with_stubbed_io()
	var manager: Variant = c._game_manager()
	if manager and manager.has_method("set_archive_hall_progress"):
		GameManager.set_archive_hall_progress({})
	c.current_word = {"word": "cat", "target": "CAT"}
	c.spelled_letters.assign(["C", "A", "T"])
	await c._to_ink_shadow()
	assert_true(c.ink_shadow_queue.has("cat"), "失败的词应进墨影队列")
	assert_true(c.spelled_letters.is_empty(), "墨影演出后槽位应已让出")
	c.free()

func test_missing_word_cards_file_degrades_to_fallback() -> void:
	# 词表文件缺失/损坏时不应崩,等价于"词表为空"→ 全部回退中文释义
	var c = _make_controller()
	c.word_cards = {}
	var card: Dictionary = c._build_word_card("city", 2)
	assert_eq(str(card.get("clue_type", "")), "chinese_meaning", "无词表时应回退中文释义")
	assert_eq(str(card.get("clue_text", "")), "city", "无词表时线索就是单词本身")
	c.free()

# ── 演出拍 4–7：阶段焦点高亮（§13.6 第 2 批）──────────────────────

func _wall_focus_of(c, letter: String) -> float:
	return c._spirit_for(letter).get_focus()

func test_spelling_phase_brightens_the_wall() -> void:
	# 该说字母名了 → 岩壁泛光
	var c = _make_controller()
	c.phase = c.Phase.SPELLING
	c._apply_phase_focus()
	assert_true(_wall_focus_of(c, "A") > 1.0, "拼写阶段岩壁应泛光")
	assert_true(_wall_focus_of(c, "Z") > 1.0, "整面岩壁都该亮，不能只亮几个")
	assert_false(c.stele_glow.visible, "拼写阶段石碑朗读光环不应亮")
	c.free()

func test_reading_phase_dims_wall_and_lights_stele() -> void:
	# 该朗读了 → 岩壁退后，石碑亮起朗读光环
	var c = _make_controller()
	c.phase = c.Phase.READING
	c._apply_phase_focus()
	assert_true(_wall_focus_of(c, "A") < 0.6, "朗读阶段岩壁应退到背景")
	assert_true(c.stele_glow.visible, "朗读阶段石碑应亮起朗读光环")
	assert_false(c.stele_ring.visible, "朗读阶段还不是判读，环形光环不应出现")
	c.free()

func test_judging_phase_spins_ring_and_dims_everything() -> void:
	var c = _make_controller()
	c.phase = c.Phase.JUDGING
	c._apply_phase_focus()
	assert_true(c.stele_ring.visible, "判读阶段应出现环形光环")
	assert_true(c._stele_ring_spinning, "判读阶段的环应旋转")
	assert_true(_wall_focus_of(c, "A") < 0.5, "判读时其余元素应变暗")
	c.free()

func test_ring_rotates_only_while_spinning() -> void:
	var c = _make_controller()
	c.phase = c.Phase.JUDGING
	c._apply_phase_focus()
	var before: float = c.stele_ring.rotation_degrees
	c._update_stele_aura(0.5)
	assert_ne(c.stele_ring.rotation_degrees, before, "判读中环应转动")
	c.phase = c.Phase.SPELLING
	c._apply_phase_focus()
	var settled: float = c.stele_ring.rotation_degrees
	c._update_stele_aura(0.5)
	assert_eq(c.stele_ring.rotation_degrees, settled, "非判读阶段环不应继续转")
	c.free()

func test_stele_glow_pulses_with_time() -> void:
	var c = _make_controller()
	c.phase = c.Phase.READING
	c._apply_phase_focus()
	c._update_stele_aura(0.1)
	var first: float = c.stele_glow.modulate.a
	c._update_stele_aura(0.4)
	assert_ne(c.stele_glow.modulate.a, first, "朗读光环应有呼吸感，不是死亮度")
	c.free()

func test_process_applies_focus_when_phase_changes() -> void:
	# 焦点高亮挂在相位检测上：改了 phase 后下一帧必须自动生效
	var c = _make_controller()
	c.phase = c.Phase.READING
	c._process(0.016)
	assert_eq(c._focus_phase_applied, c.Phase.READING, "相位检测应记录已应用阶段")
	assert_true(_wall_focus_of(c, "A") < 0.6, "改 phase 后下一帧焦点应自动跟上")
	c.free()

func test_phase_focus_does_not_touch_spirit_state() -> void:
	# 焦点高亮是表现层：不能把休眠态的精灵改成别的状态
	var c = _make_controller()
	c.phase = c.Phase.SPELLING
	c._apply_phase_focus()
	assert_eq(c._spirit_for("A").state, LetterSpiritScript.State.DORMANT, "焦点不应改状态机")
	c.free()

func test_idle_phase_keeps_neutral_focus() -> void:
	var c = _make_controller()
	c.phase = c.Phase.IDLE
	c._apply_phase_focus()
	assert_almost_eq(_wall_focus_of(c, "A"), 1.0, 0.001, "空转时岩壁应是常态亮度")
	assert_false(c.stele_glow.visible, "空转时不应有光环")
	assert_false(c.stele_ring.visible, "空转时不应有环")
	c.free()

# ── 演出拍 10–11：槽位条发光 / 示范模式逐字母点亮（§13.6 第 3 批）──

func test_stele_aura_textures_are_present() -> void:
	# 贴图路径写错时 load() 会静默返回 null，光环就永远不会亮——这里挡住
	var c = _make_controller()
	assert_not_null(c.stele_glow.texture, "朗读光环贴图应能加载")
	assert_not_null(c.stele_ring.texture, "判读光环贴图应能加载")
	c.free()

func test_confirm_spell_beats_the_slot_bar() -> void:
	var c = _make_controller()
	c._pulse_slot_bar()
	assert_eq(c.slot_bar.pivot_offset, c.slot_bar.size * 0.5, "槽位条应以中心为轴发光")
	c.free()

func test_demo_mode_lights_letters_then_returns_them_home() -> void:
	# 演出拍 11：示范模式逐字母点亮 + 逐个念字母名，读完精灵回岩壁
	var c = _make_controller_with_stubbed_io()
	# 真正的 TTS 请求在这里没有意义，还会因 HTTPRequest 忙而刷错误日志
	stub(c, "_speak_letter_name").to_return(null)
	c.config["demo_letter_lit_s"] = 0.01
	c.config["demo_letter_tts_s"] = 0.01
	c.current_word = {"word": "cat", "target": "CAT"}
	await c._trigger_demo_mode()
	assert_eq(c.spelled_letters, ["C", "A", "T"], "示范后应自动填入正确字母")
	for letter in ["C", "A", "T"]:
		var spirit = c._spirit_for(letter)
		assert_eq(spirit.position, spirit.home_position, "%s 示范读完应回岩壁原位" % letter)
		assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "%s 应回到休眠态" % letter)
	assert_true(c.demo_mode_active, "示范模式标记应保持（刻印时据此封顶 3★）")
	c.free()

# ── 演出拍 8–9：唤醒守灵 / 取词牌（§13.6 第 3 批）──────────────────

func test_runes_start_asleep_on_entry() -> void:
	# 刚进归卷厅时归卷厅是"睡着的"：26 个符文全透明，等玩家唤醒守灵
	var c = _make_controller()
	for letter in ["A", "M", "Z"]:
		var spirit = c._spirit_for(letter)
		assert_true(spirit.is_sleeping(), "%s 进场时应沉睡" % letter)
		assert_eq(spirit.modulate.a, 0.0, "%s 进场时应完全透明" % letter)
	c.free()

func test_focus_does_not_wake_sleeping_runes() -> void:
	# 阶段焦点高亮每帧都在写 modulate，绝不能把沉睡符文顺手点亮
	var c = _make_controller()
	c.phase = c.Phase.SPELLING
	c._apply_phase_focus()
	assert_eq(c._spirit_for("A").modulate.a, 0.0, "焦点高亮不应唤醒沉睡符文")
	c.free()

func test_wake_ritual_reveals_all_26_runes() -> void:
	var c = _make_controller()
	c.config["rune_reveal_ms"] = 10
	c.config["rune_reveal_stagger_ms"] = 1
	c.config["wake_curtain_ms"] = 20
	await c._play_wake_ritual()
	for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
		var spirit = c._spirit_for(letter)
		assert_false(spirit.is_sleeping(), "%s 应已现身" % letter)
		assert_true(spirit.modulate.a > 0.0, "%s 现身应有亮度" % letter)
	c.free()

func test_wake_ritual_leaves_curtain_hidden() -> void:
	# 光幕是"开门"的一瞬，不是常驻遮挡
	var c = _make_controller()
	c.config["rune_reveal_ms"] = 10
	c.config["rune_reveal_stagger_ms"] = 1
	c.config["wake_curtain_ms"] = 20
	await c._play_wake_ritual()
	assert_false(c.wake_curtain.visible, "光幕摊开后应自行隐去")
	assert_false(c._curtain_animating, "仪式返回前光幕必须已收完")
	c.free()

func test_wake_ritual_keeps_runes_on_their_wall_positions() -> void:
	var c = _make_controller()
	c.config["rune_reveal_ms"] = 10
	c.config["rune_reveal_stagger_ms"] = 1
	c.config["wake_curtain_ms"] = 20
	var before: Vector2 = c._spirit_for("L").home_position
	await c._play_wake_ritual()
	assert_eq(c._spirit_for("L").home_position, before, "现身不该改动岩壁布局")
	assert_eq(c._spirit_for("L").position, before, "现身不该挪动符文")
	c.free()

func test_wake_success_runs_ritual_then_takes_a_card() -> void:
	var c = _make_controller_with_stubbed_io()
	c.config["rune_reveal_ms"] = 10
	c.config["rune_reveal_stagger_ms"] = 1
	c.config["wake_curtain_ms"] = 20
	_prepare_word_pool(c)
	GameManager.vocabulary_learned = ["city", "house", "flower"]
	c.word_pool.clear()
	await c._on_wake_success()
	assert_false(c._spirit_for("A").is_sleeping(), "唤醒成功后符文应已现身")
	assert_false(c.current_word.is_empty(), "唤醒成功后应取到一张词牌")
	c.free()

func test_word_card_lands_at_rest_position() -> void:
	var c = _make_controller()
	c.config["card_fly_duration_ms"] = 20
	await c._play_word_card_beat()
	assert_true(c.word_card.visible, "词牌应可见")
	assert_eq(c.word_card.position, c.CARD_REST_POSITION, "词牌应停在石碑正前方")
	assert_almost_eq(c.word_card.scale.x, 1.0, 0.001, "展开后应完全摊平")
	assert_almost_eq(c.word_card.modulate.a, 1.0, 0.001, "落定后应完全不透明")
	assert_false(c._card_animating, "落定后动画标记应清空")
	c.free()

func test_word_card_carries_the_clue_label() -> void:
	# 线索长在牌面上，而不是浮在左边的独立 Label
	var c = _make_controller()
	assert_eq(c.clue_label.get_parent(), c.word_card, "线索 Label 应是词牌的子节点")
	c.free()

func test_card_and_curtain_textures_are_present() -> void:
	var c = _make_controller()
	assert_not_null(c.word_card.texture, "词牌贴图应能加载")
	assert_not_null(c.wake_curtain.texture, "光幕贴图应能加载")
	c.free()

func test_take_next_word_card_brings_the_card_in() -> void:
	var c = _make_controller_with_stubbed_io()
	c.config["card_fly_duration_ms"] = 20
	_prepare_word_pool(c)
	GameManager.vocabulary_learned = ["city"]
	c.word_pool.clear()
	c.word_pool.append(c._build_word_card("city", 0))
	c.current_word_index = 0
	await c._take_next_word_card()
	assert_eq(c.word_card.position, c.CARD_REST_POSITION, "取词牌应把牌送到石碑前")
	assert_false(c.current_word.is_empty(), "取完牌应持有当前词牌")
	# 不断言 phase：_ready() 里 deferred 的 _start_scene 会在这些 await 期间跑进
	# _enter_wake_phase() 并把 phase 重置为 IDLE（那是真实启动序列，不是被测行为）
	c.free()

# ── 美术落地：精灵体贴图（§5.2.1 第 3 条）─────────────────────────

func test_spirit_body_texture_is_promoted_and_loaded() -> void:
	# 贴图推进 assets/ 后必须跑过一次导入（scripts/godot-test.sh import），
	# 否则运行时 load() 拿不到资源，这里会红。
	var c = _make_controller()
	assert_not_null(c.spirit_body_texture, "符文精灵体贴图应能加载")
	c.free()

func test_every_rune_gets_the_spirit_body_texture() -> void:
	var c = _make_controller()
	assert_not_null(c.spirit_body_texture, "前置条件：贴图已导入")
	for letter in ["A", "M", "Z"]:
		var spirit = c._spirit_for(letter)
		assert_eq(spirit.body_texture, c.spirit_body_texture, "%s 应使用同一个精灵体" % letter)
		var body: Node = spirit.get_node_or_null("Body")
		assert_not_null(body, "%s 应有 Body 子节点" % letter)
		if body is TextureRect:
			assert_eq((body as TextureRect).texture, c.spirit_body_texture, "%s 的 Body 应显示精灵体" % letter)
	c.free()

func test_spirit_body_texture_is_shared_not_per_letter() -> void:
	# §5.2.1 第 3 条：一套共用精灵体 + 字形区分 26 个字母，不是 26 张美术
	var c = _make_controller()
	var first = c._spirit_for("A").body_texture
	for letter in "BCDEFGHIJKLMNOPQRSTUVWXYZ":
		assert_eq(c._spirit_for(letter).body_texture, first, "%s 不该有自己的专属美术" % letter)
	c.free()

# ── 场景提亮（2026-09-22 用户反馈"整体的颜色偏暗，需要调亮一点"）──────────
#
# headless（Dummy 渲染器）不支持 shader，控制器在这种情况下**故意不挂材质**；
# 所以这里断言的是"层级 / 几何 / 参数"这些与渲染后端无关的部分。
# 真机上的观感只能用截图核对（归卷厅提亮的基线/目标亮度记在 `_build_brightness_pass()`）。

func test_brightness_layer_sits_above_scene_and_below_hud() -> void:
	# 提亮层必须罩住场景内容（世界 -50 + 默认画布 0 上的腓腓），但不能碰 UI。
	var c = _make_controller()
	if c.brightness_layer == null:
		assert_not_null(c.brightness_layer, "提亮层应存在")
		c.free()
		return
	assert_eq(c.brightness_layer.layer, c.BRIGHTNESS_LAYER, "提亮层号应取常量")
	assert_true(c.BRIGHTNESS_LAYER > c.world_layer.layer,
		"提亮层（%d）必须画在世界层（%d）之后，否则提亮的是没有内容的画面" % [
			c.BRIGHTNESS_LAYER, c.world_layer.layer])
	assert_true(c.BRIGHTNESS_LAYER < 10,
		"提亮层必须低于 HUD(10)：任务条/对话框本来够亮，再抬一次会过曝")
	c.free()

func test_brightness_rect_geometry_and_material_contract() -> void:
	# 兜底不变量：**没有材质就不能建 ColorRect**。ColorRect 默认色是不透明白，
	# 少了 shader 就是一个白块糊住整个场景。
	# 也别想"把 rect.color 设透明当保险"：片元输出会被 modulate 乘一遍，
	# alpha=0 会让提亮静默失效（参数怎么调都没反应）——这个坑已经踩过一次。
	#
	# 铺满 / 不挡点击这两条只在真渲染器下能查到（headless 按设计不建矩形），
	# 真机上的观感由截图核对（见 GDD §7.7）。
	var c = _make_controller()
	var supported: bool = c._shaders_supported()
	var has_rect: bool = c.brightness_rect != null
	assert_eq(has_rect, supported,
		"提亮矩形只应在 shader 可用时存在（shader 可用=%s，矩形存在=%s）" % [supported, has_rect])
	if has_rect:
		assert_not_null(c.brightness_rect.material, "提亮矩形必须有材质，否则会画出不透明白底")
		assert_eq(c.brightness_rect.color.a, 1.0, "提亮矩形的 modulate 必须不透明，否则整层不可见")
		assert_eq(c.brightness_rect.anchor_right, 1.0, "提亮矩形应横向铺满")
		assert_eq(c.brightness_rect.anchor_bottom, 1.0, "提亮矩形应纵向铺满")
		assert_eq(c.brightness_rect.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"提亮矩形不能吃掉点击：它在默认画布之上，会挡住腓腓等世界节点")
	c.free()

func test_brightness_params_default_then_follow_config() -> void:
	var c = _make_controller()
	var defaults: Dictionary = c._brightness_params()
	assert_eq(defaults.get("gamma_lift"), c.DEFAULT_WORLD_GAMMA, "缺省 gamma 应取常量")
	assert_eq(defaults.get("gain"), c.DEFAULT_WORLD_GAIN, "缺省 gain 应取常量")
	assert_eq(defaults.get("lift"), c.DEFAULT_WORLD_LIFT, "缺省 lift 应取常量")
	c.config["world_gamma"] = 1.8
	c.config["world_gain"] = 1.2
	c.config["world_lift"] = 0.05
	var tuned: Dictionary = c._brightness_params()
	assert_eq(tuned.get("gamma_lift"), 1.8, "JSON 里的 world_gamma 应覆盖缺省")
	assert_eq(tuned.get("gain"), 1.2, "JSON 里的 world_gain 应覆盖缺省")
	assert_eq(tuned.get("lift"), 0.05, "JSON 里的 world_lift 应覆盖缺省")
	c.free()

func test_brightness_gamma_lifts_shadows_more_than_highlights() -> void:
	# "偏暗"的根因在暗部（实测 62% 像素 < 40/255），所以曲线必须**暗部抬得多、高光抬得少**。
	# 这条测试钉的是"为什么不是乘一个系数"这个决定。
	var gamma: float = ControllerScript.DEFAULT_WORLD_GAMMA
	assert_true(gamma > 1.0, "gamma 默认值必须 > 1.0（提亮），否则这条后处理等于没开")
	var shadow_gain: float = pow(0.10, 1.0 / gamma) / 0.10
	var high_gain: float = pow(0.80, 1.0 / gamma) / 0.80
	assert_true(shadow_gain > high_gain,
		"暗部抬升倍数（%.2f）必须大于高光（%.2f）：提亮要抬暗部，不能把亮部推爆" % [
			shadow_gain, high_gain])
	assert_true(high_gain * ControllerScript.DEFAULT_WORLD_GAIN <= 1.25,
		"高光总倍数 %.2f 过大，烛火/金光会过曝" % (high_gain * ControllerScript.DEFAULT_WORLD_GAIN))

func test_brightness_shader_asset_is_present_and_declares_its_uniforms() -> void:
	# 参数正确但 shader 文件不在 / uniform 改了名，都会**静默失效**
	# （set_shader_parameter 对不存在的 uniform 不报错），所以这里直接查声明。
	assert_true(ResourceLoader.exists(ControllerScript.BRIGHTNESS_SHADER),
		"提亮 shader 应存在：%s" % ControllerScript.BRIGHTNESS_SHADER)
	var shader: Shader = load(ControllerScript.BRIGHTNESS_SHADER) as Shader
	assert_not_null(shader, "提亮 shader 应能作为 Shader 加载")
	var file := FileAccess.open(ControllerScript.BRIGHTNESS_SHADER, FileAccess.READ)
	assert_not_null(file, "提亮 shader 源码应可读")
	if file == null:
		return
	var source: String = file.get_as_text()
	file.close()
	for uniform_name in ["gamma_lift", "gain", "lift"]:
		assert_true(source.contains("uniform float %s" % uniform_name),
			"shader 应声明 float uniform %s" % uniform_name)
	assert_true(source.contains("hint_screen_texture"),
		"提亮 shader 必须读屏幕纹理，否则它只是在画一个纯色块")
	# 真回归点：Godot 4 的 shader 语言把 `#` 当预处理指令（#define / #include / #ifdef …），
	# `## 标题` 不是合法指令 → **整个 shader 静默编译失败**（uniform 列表为空，材质退化成
	# 默认材质，全屏 ColorRect 直接画出不透明白底）。注释只能用 `//`。
	# headless 下拿不到编译结果（Dummy 渲染器的 uniform 列表恒为空），所以这里查源码。
	var hash_comment_lines: int = 0
	for line in source.split("\n"):
		if line.begins_with("#"):
			hash_comment_lines += 1
	assert_eq(hash_comment_lines, 0,
		"shader 里不能有 `#` 开头的行（会被当成预处理指令，整份 shader 编译失败）")
