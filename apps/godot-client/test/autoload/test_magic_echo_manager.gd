extends GutTest

const MagicEchoManagerScript = preload("res://assets/scripts/autoload/MagicEchoManager.gd")

var manager: MagicEchoManagerClass

func before_each() -> void:
	manager = MagicEchoManagerScript.new()
	add_child_autofree(manager)

func test_enter_learning_scene_creates_active_session_and_timeline() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var timeline := manager.get_timeline_events(session.get("game_session_id", ""))

	assert_eq(session.get("status", ""), "active", "学习场景应创建active GameSession")
	assert_eq(session.get("scene_id", ""), "spell_library", "场景ID应标准化")
	assert_eq(timeline.size(), 4, "进入学习场景应记录基础会话、提示和尝试事件")
	assert_eq(timeline[0].get("event_type", ""), "session_started", "第一条事件应是session_started")
	assert_eq(timeline[1].get("event_type", ""), "scene_entered", "第二条事件应是scene_entered")

func test_create_prompt_turn_stores_content_snapshot() -> void:
	var session := manager.enter_learning_scene("RainbowGarden", "child-1")
	var prompt := manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"scene_id": "rainbow_garden",
		"quest_id": "fix_weather_crystal",
		"content_id": "rainbow_weather_prompt",
		"content_version": 3,
		"prompt_text_snapshot": "Say weather words to fix the crystal.",
		"target_utterance_snapshot": "sunny",
		"expected_answer_type": "short_answer",
		"assessment_rule_version": "v1"
	})

	assert_eq(prompt.get("prompt_text_snapshot", ""), "Say weather words to fix the crystal.", "PromptTurn应保存提示文本快照")
	assert_eq(prompt.get("target_utterance_snapshot", ""), "sunny", "PromptTurn应保存目标词句快照")
	assert_eq(prompt.get("assessment_rule_version", ""), "v1", "PromptTurn应保存评分规则版本")

func test_create_interaction_attempt_is_idempotent_by_local_attempt_id() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var prompt := manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"scene_id": "spell_library",
		"quest_id": "organize_books",
		"content_id": "organize_books_prompt",
		"content_version": 1,
		"prompt_text_snapshot": "Say Big Book.",
		"target_utterance_snapshot": "big book",
		"expected_answer_type": "repeat_sentence",
		"assessment_rule_version": "v1"
	})

	var first := manager.create_interaction_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"local_attempt_id": "attempt-123"
	})
	var second := manager.create_interaction_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"local_attempt_id": "attempt-123"
	})

	assert_eq(first.get("interaction_attempt_id", ""), second.get("interaction_attempt_id", ""), "重复local_attempt_id应复用同一InteractionAttempt")
	assert_eq(manager.get_interaction_attempts_for_session(session.get("game_session_id", "")).size(), 2, "重复尝试不应创建额外记录")

func test_query_session_returns_session_prompts_attempts_and_timeline() -> void:
	var session := manager.enter_learning_scene("RainbowGarden", "child-1")
	var prompt := manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"scene_id": "rainbow_garden",
		"quest_id": "plant_flowers",
		"content_id": "plant_flowers_prompt",
		"content_version": 1,
		"prompt_text_snapshot": "Say Plant Red.",
		"target_utterance_snapshot": "plant red",
		"expected_answer_type": "repeat_sentence",
		"assessment_rule_version": "v1"
	})
	manager.create_interaction_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"local_attempt_id": "attempt-456"
	})

	var query := manager.query_game_session(session.get("game_session_id", ""))

	assert_eq(query.get("game_session", {}).get("game_session_id", ""), session.get("game_session_id", ""), "查询应包含GameSession")
	assert_eq(query.get("prompt_turns", []).size(), 2, "查询应包含PromptTurn")
	assert_eq(query.get("interaction_attempts", []).size(), 2, "查询应包含InteractionAttempt")
	assert_true(query.get("timeline_events", []).size() >= 5, "查询应包含基础TimelineEvent")

func test_enter_learning_scene_creates_queryable_prompt_and_attempt() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var query := manager.query_game_session(session.get("game_session_id", ""))

	assert_eq(query.get("prompt_turns", []).size(), 1, "进入学习场景应创建最小PromptTurn")
	assert_eq(query.get("interaction_attempts", []).size(), 1, "进入学习场景应创建最小InteractionAttempt")
	assert_eq(query.get("prompt_turns", [])[0].get("expected_answer_type", ""), "scene_entry", "最小PromptTurn应标记为scene_entry")

func test_create_prompt_turn_rejects_missing_session() -> void:
	var prompt := manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": "missing-session",
		"scene_id": "spell_library",
		"quest_id": "organize_books"
	})

	assert_true(prompt.is_empty(), "不存在的GameSession不应创建PromptTurn")

func test_create_interaction_attempt_rejects_missing_prompt() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var attempt := manager.create_interaction_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": "missing-prompt",
		"local_attempt_id": "attempt-missing"
	})

	assert_true(attempt.is_empty(), "不存在的PromptTurn不应创建InteractionAttempt")

func test_tracker_creates_session_when_game_manager_scene_changes() -> void:
	var original_scene: String = GameManager.current_scene
	var original_player_name: String = GameManager.player_name
	GameManager.current_scene = "SpellLibrary"
	GameManager.player_name = "child-1"

	manager.call("_track_current_learning_scene")
	var active := manager.get_active_session("child-1")

	assert_eq(active.get("scene_id", ""), "spell_library", "场景变化应创建active GameSession")

	GameManager.current_scene = original_scene
	GameManager.player_name = original_player_name

func test_export_import_round_trip_preserves_queryable_state() -> void:
	var session := manager.enter_learning_scene("RainbowGarden", "child-1")
	var exported := manager.export_state()
	var restored: MagicEchoManagerClass = MagicEchoManagerScript.new()
	add_child_autofree(restored)
	restored.import_state(exported)
	var query := restored.query_game_session(session.get("game_session_id", ""))

	assert_eq(query.get("game_session", {}).get("game_session_id", ""), session.get("game_session_id", ""), "导入后应能查询GameSession")
	assert_eq(query.get("prompt_turns", []).size(), 1, "导入后应保留PromptTurn")
	assert_eq(query.get("interaction_attempts", []).size(), 1, "导入后应保留InteractionAttempt")
	assert_true(query.get("timeline_events", []).size() >= 4, "导入后应保留TimelineEvent")

func test_prepare_recording_attempt_creates_pending_envelope() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var prompt := _create_prompt(session, "repeat_sentence")
	var envelope := manager.prepare_recording_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"attempt_type": "repeat_sentence"
	})
	var timeline := manager.get_timeline_events(session.get("game_session_id", ""))

	assert_false(str(envelope.get("local_attempt_id", "")).is_empty(), "录音前应生成local_attempt_id")
	assert_false(str(envelope.get("local_recording_id", "")).is_empty(), "录音前应生成local_recording_id")
	assert_eq(envelope.get("status", ""), "recording_pending", "录音envelope应处于pending状态")
	assert_eq(manager.recording_envelopes.get(envelope.get("local_recording_id", ""), {}).get("local_attempt_id", ""), envelope.get("local_attempt_id", ""), "Manager应保存pending envelope")
	assert_eq(manager.interaction_attempts.get(envelope.get("interaction_attempt_id", ""), {}).get("recording_status", ""), "recording_pending", "InteractionAttempt应标记录音pending")
	assert_true(_timeline_has_event(timeline, "recording_pending_created"), "录音前应记录timeline事件")

func test_complete_recording_attempt_writes_pending_upload_without_blocking() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var prompt := _create_prompt(session, "repeat_sentence")
	var envelope := manager.prepare_recording_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"attempt_type": "repeat_sentence"
	})
	var audio := PackedByteArray([1, 2, 3, 4, 5, 6])
	var result := manager.complete_recording_attempt(envelope.get("local_recording_id", ""), audio, {"completion_reason": "speech_detected"})
	var uploads := manager.get_pending_uploads()
	var upload: Dictionary = uploads[0]
	var timeline := manager.get_timeline_events(session.get("game_session_id", ""))

	assert_eq(result.get("status", ""), "pending_upload", "有效录音应进入pending_upload")
	assert_eq(uploads.size(), 1, "有效录音应创建待补传项")
	assert_eq(upload.get("local_attempt_id", ""), envelope.get("local_attempt_id", ""), "上传项应绑定local_attempt_id")
	assert_eq(upload.get("local_recording_id", ""), envelope.get("local_recording_id", ""), "上传项应绑定local_recording_id")
	assert_eq(upload.get("interaction_attempt_id", ""), envelope.get("interaction_attempt_id", ""), "上传项应绑定InteractionAttempt")
	assert_true(FileAccess.file_exists(upload.get("recording_file_path", "")), "本地录音文件应存在")
	assert_eq(manager.interaction_attempts.get(envelope.get("interaction_attempt_id", ""), {}).get("recording_status", ""), "pending_upload", "InteractionAttempt应标记pending_upload")
	assert_true(_timeline_has_event(timeline, "recording_saved_locally"), "保存录音后应记录timeline事件")

func test_no_speech_keeps_attempt_without_uploading_audio() -> void:
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var prompt := _create_prompt(session, "repeat_sentence")
	var envelope := manager.prepare_recording_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"attempt_type": "repeat_sentence"
	})
	var result := manager.complete_recording_attempt(envelope.get("local_recording_id", ""), PackedByteArray(), {"completion_reason": "no_speech_detected"})
	var timeline := manager.get_timeline_events(session.get("game_session_id", ""))

	assert_eq(result.get("status", ""), "no_speech_detected", "无语音应记录no_speech_detected状态")
	assert_eq(manager.get_pending_uploads().size(), 0, "无语音不应进入上传队列")
	assert_eq(manager.interaction_attempts.get(envelope.get("interaction_attempt_id", ""), {}).get("recording_status", ""), "no_speech_detected", "InteractionAttempt应保留无语音状态")
	assert_true(_timeline_has_event(timeline, "no_speech_detected"), "无语音应记录timeline事件")

func test_max_duration_recording_is_saved_and_flagged() -> void:
	var session := manager.enter_learning_scene("RainbowGarden", "child-1")
	var prompt := _create_prompt(session, "short_answer")
	var envelope := manager.prepare_recording_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"attempt_type": "short_answer"
	})
	var result := manager.complete_recording_attempt(envelope.get("local_recording_id", ""), PackedByteArray([9, 8, 7, 6]), {"completion_reason": "max_duration_reached"})
	var timeline := manager.get_timeline_events(session.get("game_session_id", ""))

	assert_eq(result.get("status", ""), "pending_upload", "达到硬上限但有音频时仍应入队")
	assert_eq(result.get("completion_reason", ""), "max_duration_reached", "上传项应标记硬上限原因")
	assert_true(_timeline_has_event(timeline, "max_duration_reached"), "硬上限应记录timeline事件")

func test_export_import_preserves_recording_queue_state() -> void:
	var session := manager.enter_learning_scene("RainbowGarden", "child-1")
	var prompt := _create_prompt(session, "short_answer")
	var envelope := manager.prepare_recording_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"attempt_type": "short_answer"
	})
	manager.complete_recording_attempt(envelope.get("local_recording_id", ""), PackedByteArray([1, 1, 1, 1]), {"completion_reason": "speech_detected"})
	var restored: MagicEchoManagerClass = MagicEchoManagerScript.new()
	add_child_autofree(restored)
	restored.import_state(manager.export_state())

	assert_eq(restored.get_pending_uploads().size(), 1, "导入后应保留pending_upload")
	assert_true(restored.recording_envelopes.has(envelope.get("local_recording_id", "")), "导入后应保留recording envelope")

func test_reconcile_local_recordings_removes_orphan_files() -> void:
	_cleanup_recording_dir()
	var orphan_path := "user://magic_echo_recordings/orphan-test.pcm"
	var file := FileAccess.open(orphan_path, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3]))
	file.close()
	var result := manager.reconcile_local_recordings()

	assert_true(int(result.get("removed_orphans", 0)) >= 1, "孤儿录音文件应被清理")
	assert_false(FileAccess.file_exists(orphan_path), "孤儿文件不应继续存在")

func _create_prompt(session: Dictionary, answer_type: String) -> Dictionary:
	return manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"scene_id": session.get("scene_id", ""),
		"quest_id": "recording_test",
		"content_id": "recording_prompt",
		"content_version": 1,
		"prompt_text_snapshot": "Say the target phrase.",
		"target_utterance_snapshot": "target phrase",
		"expected_answer_type": answer_type,
		"assessment_rule_version": "v1"
	})

func _timeline_has_event(timeline: Array, event_type: String) -> bool:
	for event in timeline:
		if str(event.get("event_type", "")) == event_type:
			return true
	return false

func _cleanup_recording_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://magic_echo_recordings")
	if FileAccess.file_exists("user://magic_echo_recordings/orphan-test.pcm"):
		DirAccess.remove_absolute("user://magic_echo_recordings/orphan-test.pcm")

func test_import_state_recovers_idempotency_without_crashing_on_stale_mapping() -> void:
	manager.import_state({
		"game_sessions": {},
		"prompt_turns": {},
		"interaction_attempts": {},
		"timeline_events_by_session": {},
		"active_session_by_child": {},
		"attempt_id_by_child_and_local_id": {"child-1:attempt-stale": "missing-attempt"},
		"next_id": 1
	})
	var session := manager.enter_learning_scene("SpellLibrary", "child-1")
	var prompt := manager.create_prompt_turn({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"scene_id": "spell_library",
		"quest_id": "organize_books",
		"content_id": "organize_books_prompt",
		"content_version": 1,
		"prompt_text_snapshot": "Say Big Book.",
		"target_utterance_snapshot": "big book",
		"expected_answer_type": "repeat_sentence",
		"assessment_rule_version": "v1"
	})
	var attempt := manager.create_interaction_attempt({
		"child_id": "child-1",
		"game_session_id": session.get("game_session_id", ""),
		"prompt_turn_id": prompt.get("prompt_turn_id", ""),
		"local_attempt_id": "attempt-stale"
	})

	assert_false(attempt.is_empty(), "陈旧幂等映射不应导致运行时报错")

func test_same_child_does_not_keep_two_active_sessions() -> void:
	var first := manager.enter_learning_scene("SpellLibrary", "child-1")
	var second := manager.enter_learning_scene("RainbowGarden", "child-1")
	var first_query := manager.query_game_session(first.get("game_session_id", ""))
	var active := manager.get_active_session("child-1")

	assert_eq(first_query.get("game_session", {}).get("status", ""), "ended", "新学习场景应结束旧active session")
	assert_eq(first_query.get("game_session", {}).get("end_reason", ""), "scene_switch", "旧session应记录scene_switch原因")
	assert_eq(active.get("game_session_id", ""), second.get("game_session_id", ""), "同一child只保留一个active session")
