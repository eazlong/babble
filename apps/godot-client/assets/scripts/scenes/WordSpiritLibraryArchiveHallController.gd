## 词灵归卷厅场景控制器（纯语音交互）
##
## Implements design doc `design/gdd/word-spirit-library-scene.md` v0.2.
## 纯语音：唤醒守灵 → 取词牌 → 说字母召唤精灵 → 拼写确认 → 朗读 → ASR 判定 →
## 刻印/墨影 → 星星奖励 → 下一张/退出。
##
## 合规要点（CLAUDE.md）：
## - §2 录音流程统一由 VoicePipeline 控制，场景不自实现硬上限/duck。
## - §3 录音前传 recording_context，game_session_id/prompt_turn_id 由 MagicEchoManager 自动补齐。
## - §4 no-speech 不上传音频、保留 InteractionAttempt、记录 timeline event。
## - §5 录音硬上限从 start_listening() 后计算，由 VoicePipeline.max_duration_reached 处理。
## - §6 duck 由 VoicePipeline 成对处理，场景不调用 duck。
## - §7 ASR 结果统一通过 HybridAPI helper 读取，不直接读 result.postprocess.*。
## - §8 字母/指令分类由客户端完成（voice-service 只出 provide/delegate/off_topic）。
## - §11 切场景用 call_deferred。
## - §12 UI 状态来自 autoload 真实状态。
##
## 实现偏离设计文档说明（coordinator 已确认，方案 B）：
## - §5.3/§6.4 声明 intent=letter_name/command 由 voice-service 出。实际 voice-service
##   只出 provide/delegate/off_topic（ADR-0001）。本控制器用 HybridAPI.get_asr_corrected_text
##   拿到文本后，本地用配置里的 letter_name_map / command_words 做字母/指令分类。
##   行为等价，边界清晰，不碰 voice-service。
## - §5.3 字母置信度用 result.postprocess.confidence（Whisper language_probability）作近似，
##   阈值照搬设计文档默认（0.80/0.55）。这是近似值，上线后用 letter_recognition_record
##   数据校准。
extends Node2D

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")

const CONFIG_PATH: String = "res://assets/data/word_spirit_library_scene.json"
const VIEW_SIZE: Vector2 = Vector2(1920, 1080)
const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
const FEIFEI_SPEAKER: String = "feifei"
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## 阶段状态机（设计文档 §4.3）
enum Phase {
	IDLE,            ## 空转，等待取词牌
	SPELLING,        ## 拼写阶段：监听字母名/指令
	SPELL_CONFIRM,   ## 玩家说 done，判定拼写是否正确
	READING,         ## 朗读阶段：监听单词发音
	JUDGING,         ## ASR 判定中
	PLAYBACK_REVIEW, ## ASR 不可用降级：录音回放自评
	SCATTERING,      ## 散落动画
	INSCRIBING,      ## 刻印动画 + 星星发放
	COMPLETE,        ## 词牌清空，等待 next/leave
	EXITING,         ## 退出确认中
}

@onready var feifei: FeifeiShoulder = get_node_or_null("FeifeiLayer/FeifeiShoulder")
@onready var mic_button: Control = get_node_or_null("MicLayer/MicButton")
@onready var quest_label: Label = get_node_or_null("HUDLayer/QuestTracker/QuestLabel")

var config: Dictionary = {}
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()

var phase: Phase = Phase.IDLE
var word_pool: Array[Dictionary] = []
var current_word_index: int = 0
var current_word: Dictionary = {}
var spelled_letters: Array[String] = []
var reading_attempts: int = 0
var spell_error_count: int = 0
var consecutive_ink_shadow: int = 0
var consecutive_no_speech: int = 0
var demo_mode_active: bool = false
var stars_this_session: int = 0
var inscribed_count: int = 0
var ink_shadow_queue: Array[String] = []

var _voice_listening: bool = false
var _asr_request_active: bool = false
## 当前录音绑定的交互尝试 ID，ASR 评分后回写 MagicEchoManager 供掌握度聚合。
var _current_attempt_id: String = ""
var _silence_timer: float = 0.0
var _letter_cooldown_timer: float = 0.0
var _confirm_letter: String = ""  ## 守灵复述确认中的字母
var _confirm_count: int = 0
var _exit_pending: bool = false
var _first_spelling_prompted: bool = false
var _first_reading_prompted: bool = false
var _first_undo_prompted: bool = false
var _rest_card_counter: int = 0

var world_layer: CanvasLayer
var visual_root: Control
var stele_label: Label
var slot_bar: HBoxContainer
var clue_label: Label
var star_label: Label
var ink_shadow_label: Label
var phase_label: Label

func _ready() -> void:
	var manager: Variant = _game_manager()
	if manager:
		manager.set_checkpoint("WordSpiritLibraryArchiveHall", not manager.is_test_mode_skip_auto_load_save())
	_load_config()
	dialogue_flow_loader.load_dialogue_flows()
	_build_visuals()
	_connect_runtime_signals()
	_restore_progress()
	if mic_button:
		mic_button.visible = false
	call_deferred("_start_scene")
	
	HybridAPI.set_asr_default_answer_test_enabled(true, "res://assets/test_audio/",
		["hello.wav", "letter_a.wav", "letter_p.wav", "letter_p.wav", "letter_l.wav", "letter_e.wav", "done.wav", "apple.wav", "next.wav"])
	

func _process(delta: float) -> void:
	if _letter_cooldown_timer > 0.0:
		_letter_cooldown_timer -= delta
	if not _voice_listening:
		return
	# 沉默提示（设计文档 §11.2）。沉默不消耗资源，不扣星。
	_silence_timer += delta
	var spark_delay: float = float(config.get("silence_to_spark_prompt_s", 10.0))
	var feifei_delay: float = float(config.get("silence_to_feifei_prompt_s", 15.0))
	var exit_delay: float = float(config.get("silence_to_exit_option_s", 30.0))
	if _silence_timer >= exit_delay:
		_silence_timer = 0.0
		await _speak_flow("archive.guardian_silence_exit_option", "en", 1.5)
	elif _silence_timer >= feifei_delay and phase in [Phase.SPELLING, Phase.READING]:
		_silence_timer = 0.0
		await _speak_flow("archive.spark_spell_hint" if phase == Phase.SPELLING else "archive.spark_reading_hint", "en", 1.2)
	elif _silence_timer >= spark_delay:
		_silence_timer = 0.0
		await _speak_flow("archive.spark_spell_hint" if phase == Phase.SPELLING else "archive.spark_reading_hint", "en", 1.2)
	
# ── 启动 ──────────────────────────────────────────────────────────────

func _start_scene() -> void:
	if feifei:
		feifei.visible = true
		await feifei.play_entry_fly_in()
		await feifei.settle_to_shoulder()
	_build_word_pool()
	if word_pool.is_empty():
		await _speak_flow("archive.guardian_no_words", "en", 1.8)
		return
	await _speak_flow("archive.feifei_first_intro", "zh", 1.8)
	_enter_wake_phase()

## 入口唤醒阶段：玩家对书柜说话唤醒守灵。
func _enter_wake_phase() -> void:
	phase = Phase.IDLE
	_set_quest_text("任务：对书柜守灵说话以进入归卷厅")
	_set_phase_text("唤醒守灵")
	await _speak_flow("archive.wake_guardian", "en", 1.8)
	_start_listening(_build_recording_context("wake_guardian", "archive_entry_wake", "", "open_greeting"))

# ── 词牌池 ────────────────────────────────────────────────────────────

## 词牌池生成（阻塞 5 方案：只用 GameManager.vocabulary_learned）。
## §4.2 的 60/25/15 比例留配置字段但暂以"全部来自 vocabulary_learned"占位。
## mastery/错词/遗忘曲线待 LXP 接口落地。
func _build_word_pool() -> void:
	word_pool.clear()
	var manager: Variant = _game_manager()
	var learned: Array[String] = []
	if manager:
		for w in manager.vocabulary_learned:
			var word: String = str(w).strip_edges()
			if not word.is_empty() and not learned.has(word):
				learned.append(word)
	# learned 为空时用配置里的 fallback 词池，保证场景可玩。
	if learned.is_empty():
		for entry in config.get("fallback_word_pool", []):
			if entry is Dictionary:
				word_pool.append(entry.duplicate(true))
	else:
		learned.shuffle()
		var limit: int = int(config.get("daily_word_cards", 10))
		for word_text in learned.slice(0, limit):
			word_pool.append({
				"word": word_text.to_lower(),
				"clue_type": "chinese_meaning",
				"clue_text": word_text,
				"target": word_text.to_upper(),
			})
	# 从存档恢复已完成的词牌索引。
	if current_word_index > 0 and current_word_index < word_pool.size():
		word_pool = word_pool.slice(current_word_index)

# ── 取词牌 ────────────────────────────────────────────────────────────

func _take_next_word_card() -> void:
	if current_word_index >= word_pool.size():
		_enter_complete()
		return
	current_word = word_pool[current_word_index]
	spelled_letters.clear()
	reading_attempts = 0
	spell_error_count = 0
	demo_mode_active = false
	_confirm_letter = ""
	_confirm_count = 0
	phase = Phase.SPELLING
	_first_spelling_prompted = false
	_first_reading_prompted = false
	_update_stele_visuals()
	_update_slot_visuals()
	_set_quest_text("任务：说字母名召唤精灵拼出单词")
	_set_phase_text("拼写阶段")
	# feifei 首次拼写引导（一次性）
	if not _first_spelling_prompted:
		_first_spelling_prompted = true
		await _speak_flow("archive.feifei_first_spelling", "zh", 1.2)
	else:
		await _speak_flow("archive.spark_spell_hint", "en", 1.0)
	_start_listening(_build_letter_context())

# ── 拼写阶段：字母名识别 ─────────────────────────────────────────────

func _build_letter_context() -> Dictionary:
	var word_id: String = str(current_word.get("word", ""))
	var ctx: Dictionary = _build_recording_context(
		"letter_name",
		"archive_letter_%s_%d" % [word_id, spelled_letters.size()],
		str(current_word.get("target", "")),
		"letter_name"
	)
	ctx["word_id"] = word_id
	ctx["slot_index"] = spelled_letters.size()
	ctx["clue_type"] = str(current_word.get("clue_type", "chinese_meaning"))
	return ctx

func _on_letter_voice_ended(result: Dictionary) -> void:
	# 方案 B：客户端本地分类字母/指令。
	var text: String = _hybrid_api().get_asr_corrected_text(result).strip_edges()
	var confidence: float = _hybrid_api().get_asr_confidence(result)
	var command: String = _match_command(text)
	if not command.is_empty():
		_handle_spell_command(command, text)
		return
	var letter: String = _match_letter(text)
	if letter.is_empty():
		# 非字母非指令 → off_topic 软提示
		await _speak_flow("archive.spark_spell_hint", "en", 1.0)
		_start_listening(_build_letter_context())
		return
	# 召唤冷却（设计文档 §5.5），防止连说识别堆积
	if _letter_cooldown_timer > 0.0:
		await _speak_flow("archive.spark_one_at_a_time", "en", 1.0)
		_start_listening(_build_letter_context())
		return
	_handle_letter_identified(letter, confidence)

func _handle_letter_identified(letter: String, confidence: float) -> void:
	var high: float = float(config.get("letter_high_threshold", 0.80))
	var medium: float = float(config.get("letter_medium_threshold", 0.55))
	# NOTE: confidence 是 Whisper language_probability 的近似值（阻塞 2）。
	if confidence >= high:
		_adopt_letter(letter)
		return
	if confidence >= medium:
		# 中置信度：守灵复述确认（§5.3）
		if _confirm_letter == letter and _confirm_count >= 2:
			# 仍模糊则按最高置信度采纳并高亮（玩家可 undo 撤回）
			_adopt_letter(letter)
			return
		_confirm_letter = letter
		_confirm_count += 1
		await _speak_flow("archive.guardian_confirm_letter", "en", 1.5, {"letter": letter})
		_start_listening(_build_letter_context())
		return
	# 低置信度：不填槽位，提示重说
	await _speak_flow("archive.spark_letter_unclear", "en", 1.0)
	_start_listening(_build_letter_context())

func _adopt_letter(letter: String) -> void:
	spelled_letters.append(letter)
	_letter_cooldown_timer = float(config.get("letter_summon_cooldown_ms", 600)) / 1000.0
	_confirm_letter = ""
	_confirm_count = 0
	_update_slot_visuals()
	_start_listening(_build_letter_context())

# ── 拼写指令处理（§5.4）─────────────────────────────────────────────

func _handle_spell_command(command: String, raw_text: String) -> void:
	match command:
		"undo", "back":
			_undo_last_letter()
		"clear", "reset":
			_clear_letters()
		"done", "ready", "finish":
			await _confirm_spell()
		"leave", "exit", "stop", "quit":
			_request_exit()
		"help", "hint":
			_trigger_demo_mode()
		"remove":
			var letter: String = _match_letter(raw_text.substr(6))
			if not letter.is_empty():
				_remove_letter(letter)
		"hello":
			# 入口阶段残留问候，忽略
			_start_listening(_build_letter_context())
		_:
			await _speak_flow("archive.spark_spell_hint", "en", 1.0)
			_start_listening(_build_letter_context())

func _undo_last_letter() -> void:
	if spelled_letters.is_empty():
		_start_listening(_build_letter_context())
		return
	spelled_letters.pop_back()
	if not _first_undo_prompted:
		_first_undo_prompted = true
		await _speak_flow("archive.feifei_first_undo", "zh", 1.2)
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _clear_letters() -> void:
	spelled_letters.clear()
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _remove_letter(letter: String) -> void:
	for i in range(spelled_letters.size() - 1, -1, -1):
		if spelled_letters[i] == letter:
			spelled_letters.remove_at(i)
			break
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _confirm_spell() -> void:
	phase = Phase.SPELL_CONFIRM
	_stop_listening()
	var target: String = str(current_word.get("target", ""))
	var spelled_upper: String = "".join(spelled_letters).to_upper()
	if spelled_upper == target:
		# 拼写正确 → 进入朗读阶段
		_enter_reading_phase()
		return
	# 拼写错误 → 退回 SPELLING，不消耗朗读机会（§10.3）
	spell_error_count += 1
	if spell_error_count >= int(config.get("spell_error_retry_limit", 2)):
		# 连续 2 次错误 → Spark 示范模式（§7.4），不扣星
		_trigger_demo_mode()
		return
	await _speak_flow("archive.spark_spell_error", "en", 1.2)
	phase = Phase.SPELLING
	_start_listening(_build_letter_context())

# ── 朗读阶段（§6）──────────────────────────────────────────────────

func _enter_reading_phase() -> void:
	phase = Phase.READING
	_set_quest_text("任务：朗读单词以刻印词灵")
	_set_phase_text("朗读阶段")
	_update_stele_visuals()
	if not _first_reading_prompted:
		_first_reading_prompted = true
		await _speak_flow("archive.feifei_first_reading", "zh", 1.2)
	else:
		await _speak_flow("archive.spark_reading_hint", "en", 1.0)
	_start_listening(_build_reading_context())

func _build_reading_context() -> Dictionary:
	var word_id: String = str(current_word.get("word", ""))
	var target: String = str(current_word.get("target", ""))
	var ctx: Dictionary = _build_recording_context(
		"word_pronunciation",
		"archive_word_%s" % word_id,
		target,
		"word_pronunciation"
	)
	ctx["word_id"] = word_id
	ctx["word_text"] = str(current_word.get("word", ""))
	ctx["clue_type"] = str(current_word.get("clue_type", "chinese_meaning"))
	return ctx

func _on_reading_voice_ended(result: Dictionary) -> void:
	phase = Phase.JUDGING
	var corrected: String = _hybrid_api().get_asr_corrected_text(result).strip_edges().to_lower()
	var confidence: float = _hybrid_api().get_asr_confidence(result)
	var target: String = str(current_word.get("word", "")).to_lower()
	# ASR 不可用 / result 为空 → 进入 PLAYBACK_REVIEW（§6.5）
	if corrected.is_empty() and confidence <= 0.0:
		_enter_playback_review()
		return
	# 判定（设计文档 §6.3）
	if _normalize_word(corrected) == _normalize_word(target):
		# 匹配：按共鸣度分层。confidence 即掌握度代理（0-1）。
		_report_attempt_mastery(corrected, confidence)
		if confidence >= 0.85:
			_inscribe_word(3)
		elif confidence >= 0.65:
			_inscribe_word(2)
		elif confidence >= 0.40:
			# 再试：消耗一次朗读机会
			_consume_reading_attempt()
		else:
			# 需要帮助：Spark 示范模式（不计入连续失败计数，§10.5）
			_trigger_demo_mode()
	else:
		# 识别文本与目标词不匹配 → 低掌握度，消耗一次朗读机会
		_report_attempt_mastery(corrected, min(confidence, 0.3))
		_consume_reading_attempt()

## 回写 ASR 文本与实时掌握度到当前交互尝试，供 summary-service 聚合。
func _report_attempt_mastery(asr_text: String, mastery_score: float) -> void:
	if _current_attempt_id.is_empty():
		return
	var magic_echo: Variant = get_node_or_null("/root/MagicEchoManager")
	if magic_echo and magic_echo.has_method("update_attempt_asr_result"):
		magic_echo.call("update_attempt_asr_result", _current_attempt_id, asr_text, mastery_score)
	_current_attempt_id = ""

func _consume_reading_attempt() -> void:
	reading_attempts += 1
	if reading_attempts >= int(config.get("reading_retry_limit", 2)):
		# 朗读机会耗尽 → 墨影词牌
		_to_ink_shadow()
		return
	await _speak_flow("archive.spark_reading_retry", "en", 1.2)
	phase = Phase.READING
	_start_listening(_build_reading_context())

# ── ASR 不可用降级：录音回放 + feifei 引导（§6.5）─────────────────

func _enter_playback_review() -> void:
	phase = Phase.PLAYBACK_REVIEW
	# 不上传无效音频、保留 InteractionAttempt（由 VoicePipeline/MagicEchoManager 完成）
	await _speak_flow("archive.feifei_playback_review", "zh", 1.5)
	_start_listening(_build_recording_context(
		"playback_self_eval",
		"archive_playback_%s" % str(current_word.get("word", "")),
		str(current_word.get("target", "")),
		"playback_self_eval"
	))

func _on_playback_review_command(command: String) -> void:
	match command:
		"retry", "again":
			# 重新进入 READING（消耗一次朗读机会）
			_consume_reading_attempt()
		"accept", "ok", "yes":
			# 减半星星刻印（§7.3）
			_inscribe_word(int(config.get("playback_review_star", 1)))
		"leave", "exit", "stop", "quit":
			_request_exit()
		"help", "hint":
			_trigger_demo_mode()
		_:
			_start_listening(_build_recording_context(
				"playback_self_eval",
				"archive_playback_%s" % str(current_word.get("word", "")),
				str(current_word.get("target", "")),
				"playback_self_eval"
			))

# ── 刻印 / 散落 / 墨影（§7）────────────────────────────────────────

func _inscribe_word(stars: int) -> void:
	phase = Phase.INSCRIBING
	_stop_listening()
	if demo_mode_active:
		stars = mini(stars, int(config.get("demonstration_star_cap", 1)))
	# 星星发放（阻塞 4 占位：委托 lxp，TODO 待 Star Economy stars_per_response 接口落地）
	_grant_stars(stars)
	stars_this_session += stars
	inscribed_count += 1
	_rest_card_counter += 1
	_update_stele_visuals()
	# 刻印成功表现（§7.1）
	var flow_id: String = "archive.spark_inscribe_clear" if stars >= 3 else "archive.spark_inscribe_close"
	await _speak_flow(flow_id, "en", 1.2)
	await _speak_flow("archive.guardian_next_prompt", "en", 1.2)
	# 休息提示（§11.4）
	if _rest_card_counter >= int(config.get("rest_prompt_every_n_cards", 5)):
		_rest_card_counter = 0
		await _speak_flow("archive.feifei_rest_prompt", "zh", 1.5)
	_save_progress()
	phase = Phase.COMPLETE
	# 循环监听 next/leave
	_start_listening(_build_recording_context(
		"exit_command",
		"archive_complete_%s" % str(current_word.get("word", "")),
		"",
		"exit_command"
	))

func _to_ink_shadow() -> void:
	phase = Phase.SCATTERING
	_stop_listening()
	consecutive_ink_shadow += 1
	ink_shadow_queue.append(str(current_word.get("word", "")))
	if ink_shadow_queue.size() > int(config.get("ink_shadow_soft_cap", 5)):
		await _speak_flow("archive.feifei_too_many_ink_shadow", "zh", 1.8)
	elif consecutive_ink_shadow >= 2:
		await _speak_flow("archive.feifei_consecutive_ink_shadow", "zh", 1.5)
	else:
		await _speak_flow("archive.spark_scatter", "en", 1.2)
	_update_ink_shadow_visuals()
	_save_progress()
	await get_tree().create_timer(0.5).timeout
	_advance_next_word()

func _advance_next_word() -> void:
	current_word_index += 1
	_take_next_word_card()

# ── Spark 示范模式（§7.4）──────────────────────────────────────────

func _trigger_demo_mode() -> void:
	demo_mode_active = true
	_stop_listening()
	await _speak_flow("archive.spark_demo_intro", "en", 1.2)
	# 逐字母点亮目标单词的字母精灵并播放字母名发音
	var target: String = str(current_word.get("target", ""))
	for i in range(target.length()):
		var letter: String = target[i]
		await get_tree().create_timer(0.4).timeout
		# TTS 播放字母名
		if _hybrid_api():
			_hybrid_api().synthesize_tts(letter, "spirit", "en")
		await get_tree().create_timer(0.5).timeout
	await _speak_flow("archive.spark_demo_outro", "en", 1.0)
	# 自动填入正确字母
	spelled_letters.clear()
	for i in range(target.length()):
		spelled_letters.append(target[i])
	_update_slot_visuals()
	# 示范后进入朗读阶段，不计入朗读机会消耗
	phase = Phase.READING
	_start_listening(_build_reading_context())

# ── 完成 / 退出（§3.3）─────────────────────────────────────────────

func _enter_complete() -> void:
	phase = Phase.COMPLETE
	_stop_listening()
	_set_quest_text("完成：归卷厅刻印完成")
	_set_phase_text("完成")
	await _speak_flow("archive.guardian_complete_report", "en", 1.8, {"count": str(inscribed_count)})
	_save_progress()
	_start_listening(_build_recording_context(
		"exit_command",
		"archive_session_complete",
		"",
		"exit_command"
	))

func _request_exit() -> void:
	_stop_listening()
	# 若有未完成词牌，守灵确认
	if current_word_index < word_pool.size() and not _exit_pending:
		_exit_pending = true
		phase = Phase.EXITING
		await _speak_flow("archive.guardian_exit_confirm", "en", 1.5)
		_start_listening(_build_recording_context(
			"exit_command",
			"archive_exit_confirm",
			"",
			"exit_command"
		))
		return
	_exit_scene()

func _exit_scene() -> void:
	_stop_listening()
	_save_progress()
	# 返回主菜单（§11 用 call_deferred）
	call_deferred("_do_scene_change")

func _do_scene_change() -> void:
	get_tree().change_scene_to_file("res://assets/scenes/MainMenu.tscn")

# ── 语音管线集成 ─────────────────────────────────────────────────────

func _connect_runtime_signals() -> void:
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		if not voice_pipeline.voice_ended.is_connected(_on_voice_ended):
			voice_pipeline.voice_ended.connect(_on_voice_ended)
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api and not hybrid_api.asr_received.is_connected(_on_asr_received):
		hybrid_api.asr_received.connect(_on_asr_received)

func _start_listening(recording_context: Dictionary) -> void:
	if _voice_listening:
		return
	_voice_listening = true
	_asr_request_active = false
	_silence_timer = 0.0
	if mic_button:
		mic_button.visible = true
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.start_listening(recording_context)

func _stop_listening() -> void:
	_voice_listening = false
	_silence_timer = 0.0
	if mic_button:
		mic_button.visible = false
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.stop_listening()

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	if not _voice_listening or _asr_request_active:
		return
	# voice_ended 表示一段录音已结束：必须在此重置 _voice_listening，
	# 否则后续 _adopt_letter / _handle_no_speech → _relisten 调 _start_listening 时
	# 会被 `if _voice_listening: return` 守卫拦截，下一次录音永不启动，流程卡死。
	_voice_listening = false
	# no-speech：VoicePipeline 已通过 MagicEchoManager 保留 InteractionAttempt + timeline event。
	# 场景只负责推进状态，不上传音频、不消耗资源（CLAUDE.md §4）。
	if audio_data.is_empty():
		_handle_no_speech()
		return
	# 缓存当前 attempt_id，ASR 返回后回写评分（envelope 在 finalize 后会被清空）。
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		_current_attempt_id = str(voice_pipeline.get("current_recording_envelope").get("interaction_attempt_id", ""))
	_asr_request_active = true
	# 按 phase 分派 ASR 请求
	var asr_context: Dictionary = _build_asr_request_context()
	var hybrid_api: Variant = _hybrid_api()
	if hybrid_api:
		hybrid_api.recognize_speech(audio_data, "en", asr_context)

func _handle_no_speech() -> void:
	consecutive_no_speech += 1
	if consecutive_no_speech >= int(config.get("consecutive_no_speech_to_feifei", 3)):
		consecutive_no_speech = 0
		# feifei 中文提示换环境（§10.7）
		await _speak_flow("archive.feifei_playback_review", "zh", 1.5)
	# no-speech 不消耗朗读机会、不消耗字母召唤资源（§10.4）
	# 重新开始监听当前阶段
	_relisten_current_phase()

func _relisten_current_phase() -> void:
	match phase:
		Phase.IDLE:
			_start_listening(_build_recording_context("wake_guardian", "archive_entry_wake", "", "open_greeting"))
		Phase.SPELLING:
			_start_listening(_build_letter_context())
		Phase.READING:
			_start_listening(_build_reading_context())
		Phase.PLAYBACK_REVIEW:
			_start_listening(_build_recording_context(
				"playback_self_eval",
				"archive_playback_%s" % str(current_word.get("word", "")),
				str(current_word.get("target", "")),
				"playback_self_eval"
			))
		Phase.COMPLETE:
			_start_listening(_build_recording_context(
				"exit_command",
				"archive_complete_%s" % str(current_word.get("word", "")),
				"",
				"exit_command"
			))
		Phase.EXITING:
			_start_listening(_build_recording_context(
				"exit_command",
				"archive_exit_confirm",
				"",
				"exit_command"
			))

func _on_asr_received(result: Dictionary) -> void:
	if not _asr_request_active:
		return
	_asr_request_active = false
	if result.has("error"):
		# ASR 不可用 → 朗读阶段降级为 PLAYBACK_REVIEW（§6.5）
		if phase == Phase.READING:
			_enter_playback_review()
		else:
			_relisten_current_phase()
		return
	# 按 phase 分派结果处理
	match phase:
		Phase.IDLE:
			# 入口唤醒：只接受唤醒词（hello/guardian/open 等，见 command_words.hello）。
			# 非唤醒词（含字母）不唤醒、保持 IDLE 重听——避免吞掉玩家想拼的字母。
			# 整个玩法只唤醒一次，唤醒成功后换词牌直接进 SPELLING，不再 wake。
			var wake_text: String = _hybrid_api().get_asr_corrected_text(result).strip_edges()
			if _match_command(wake_text) == "hello":
				_on_wake_success()
			else:
				_relisten_current_phase()
		Phase.SPELLING:
			_on_letter_voice_ended(result)
		Phase.READING, Phase.JUDGING:
			_on_reading_voice_ended(result)
		Phase.PLAYBACK_REVIEW:
			var text: String = _hybrid_api().get_asr_corrected_text(result).strip_edges()
			var command: String = _match_command(text)
			if command.is_empty() and _match_letter(text) != "":
				command = "accept"  # 误识别为字母时按接受处理
			_on_playback_review_command(command)
		Phase.COMPLETE, Phase.EXITING:
			_on_exit_command_received(result)

func _on_wake_success() -> void:
	_stop_listening()
	consecutive_no_speech = 0
	_take_next_word_card()

func _on_exit_command_received(result: Dictionary) -> void:
	var text: String = _hybrid_api().get_asr_corrected_text(result).strip_edges()
	var command: String = _match_command(text)
	match command:
		"next":
			_exit_pending = false
			_advance_next_word()
		"leave", "exit", "stop", "quit":
			_request_exit()
		"yes":
			if phase == Phase.EXITING:
				_exit_scene()
			else:
				_advance_next_word()
		"no":
			_exit_pending = false
			phase = Phase.SPELLING
			_start_listening(_build_letter_context())
		"help", "hint":
			_trigger_demo_mode()
		_:
			_relisten_current_phase()

# ── recording_context 构造（§6.2）──────────────────────────────────

func _build_recording_context(attempt_type: String, content_id: String, target_utterance: String, expected_answer_type: String) -> Dictionary:
	var scene_id: String = str(config.get("scene_id", "word_spirit_library_archive_hall"))
	var quest_id: String = "archive_enter" if attempt_type == "wake_guardian" else "archive_inscribe_%s" % str(current_word.get("word", ""))
	var prompt_text: String = ""
	match attempt_type:
		"wake_guardian":
			prompt_text = "对书柜守灵说话以进入归卷厅"
		"letter_name":
			prompt_text = "说一个字母召唤字母精灵"
		"word_pronunciation":
			prompt_text = "朗读单词以刻印词灵"
		"playback_self_eval":
			prompt_text = "说 retry 再试，或 accept 接受"
		"exit_command":
			prompt_text = "说 next 继续，或 leave 退出"
	var max_duration: float = _max_duration_for_attempt(attempt_type)
	return {
		"scene_id": scene_id,
		"quest_id": quest_id,
		"content_id": content_id,
		"prompt_text_snapshot": prompt_text,
		"target_utterance_snapshot": target_utterance,
		"attempt_type": attempt_type,
		"expected_answer_type": expected_answer_type,
		"max_duration": max_duration,
	}

func _max_duration_for_attempt(attempt_type: String) -> float:
	match attempt_type:
		"wake_guardian":
			return float(config.get("wake_max_duration_s", 10.0))
		"letter_name":
			return float(config.get("letter_max_duration_s", 3.0))
		"word_pronunciation":
			return float(config.get("reading_max_duration_s", 8.0))
		"playback_self_eval":
			return float(config.get("playback_review_max_duration_s", 10.0))
		"exit_command":
			return float(config.get("exit_max_duration_s", 10.0))
	return 10.0

func _build_asr_request_context() -> Dictionary:
	# 给 voice-service 的 ASR context（候选答案等）
	var target: String = str(current_word.get("word", ""))
	var answer_type: String = str(_current_expected_answer_type())
	var candidates: Array = []
	match answer_type:
		"letter_name":
			# 字母精灵：任意字母可召唤，候选为字母表（letter_name_map 的规范值 A-Z）。
			# 不能塞整个目标单词——单词不是字母候选，会让服务端封闭题匹配失真。
			var seen: Dictionary = {}
			for v in config.get("letter_name_map", {}).values():
				var letter := str(v)
				if not seen.has(letter):
					seen[letter] = true
					candidates.append(letter)
		_:
			candidates = [target] if not target.is_empty() else []
	return {
		"scene_id": str(config.get("scene_id", "word_spirit_library_archive_hall")),
		"npc_id": "archive_guardian",
		"player_level": _player_level(),
		"language": "en",
		# 归卷厅是非对话任务（字母识别/朗读/回放自评/指令），不是槽位对话题。
		# 由场景声明 task_mode，voice-service 据此跳过对话 postprocess，原样透传文本。
		"task_mode": _current_task_mode(),
		"expected_answer_type": answer_type,
		"candidate_answers": candidates,
	}

func _current_task_mode() -> String:
	# 向 voice-service 声明任务环境。非 "dialogue" 值触发服务端跳过对话 postprocess。
	match phase:
		Phase.IDLE:
			return "open_greeting"
		Phase.SPELLING, Phase.SPELL_CONFIRM:
			return "letter_recognition"
		Phase.READING, Phase.JUDGING:
			return "word_pronunciation"
		Phase.PLAYBACK_REVIEW:
			return "playback_self_eval"
		Phase.COMPLETE, Phase.EXITING:
			return "exit_command"
	return "dialogue"

func _current_expected_answer_type() -> String:
	match phase:
		Phase.SPELLING:
			return "letter_name"
		Phase.READING, Phase.JUDGING:
			return "word_pronunciation"
		Phase.PLAYBACK_REVIEW:
			return "playback_self_eval"
		Phase.COMPLETE, Phase.EXITING:
			return "exit_command"
	return "short_answer"

# ── 字母/指令本地分类（方案 B，§5.3/§5.4/§8.1）──────────────────

func _match_letter(text: String) -> String:
	if text.is_empty():
		return ""
	var cleaned: String = text.strip_edges().to_lower()
	# 去除首尾非字母字符
	var alphabet: String = "abcdefghijklmnopqrstuvwxyz "
	var i: int = 0
	while i < cleaned.length() and alphabet.find(cleaned[i]) == -1:
		i += 1
	var j: int = cleaned.length() - 1
	while j >= i and alphabet.find(cleaned[j]) == -1:
		j -= 1
	if j < i:
		return ""
	cleaned = cleaned.substr(i, j - i + 1)
	var letter_map: Dictionary = config.get("letter_name_map", {})
	if letter_map.has(cleaned):
		return str(letter_map[cleaned])
	# 单字符直接匹配
	if cleaned.length() == 1 and alphabet.find(cleaned[0]) != -1:
		return cleaned.to_upper()
	# 首词匹配
	var first_word: String = cleaned.split(" ")[0] if cleaned.find(" ") > 0 else cleaned
	if letter_map.has(first_word):
		return str(letter_map[first_word])
	return ""

func _match_command(text: String) -> String:
	if text.is_empty():
		return ""
	var cleaned: String = text.strip_edges().to_lower()
	var command_words: Dictionary = config.get("command_words", {})
	for command in command_words.keys():
		var words: Array = command_words[command]
		for w in words:
			var word: String = str(w).to_lower()
			if cleaned == word or cleaned.begins_with(word + " ") or cleaned.begins_with(word + "."):
				return str(command)
	return ""

# ── 星星发放（阻塞 4 占位）─────────────────────────────────────────

func _grant_stars(star_count: int) -> void:
	if star_count <= 0:
		return
	var multiplier: int = int(config.get("star_to_lxp_multiplier", 10))
	var manager: Variant = _game_manager()
	if manager:
		manager.lxp_score += star_count * multiplier
	# TODO: 待 Star Economy stars_per_response 接口落地后替换为正式星星发放。
	if star_label:
		star_label.text = "Stars: %d" % stars_this_session

# ── 存档（阻塞 5：GameManager 加字段）──────────────────────────────

func _save_progress() -> void:
	var manager: Variant = _game_manager()
	if manager:
		if manager.has_method("set_archive_hall_progress"):
			manager.set_archive_hall_progress({
				"current_word_index": current_word_index,
				"inscribed_count": inscribed_count,
				"stars_this_session": stars_this_session,
			})
		if manager.has_method("set_ink_shadow_queue"):
			manager.set_ink_shadow_queue(ink_shadow_queue.duplicate())
		manager.save_progress()

func _restore_progress() -> void:
	var manager: Variant = _game_manager()
	if manager:
		if manager.has_method("get_archive_hall_progress"):
			var progress: Dictionary = manager.get_archive_hall_progress()
			if not progress.is_empty():
				current_word_index = int(progress.get("current_word_index", 0))
				inscribed_count = int(progress.get("inscribed_count", 0))
				stars_this_session = int(progress.get("stars_this_session", 0))
		if manager.has_method("get_ink_shadow_queue"):
			ink_shadow_queue = manager.get_ink_shadow_queue()
	_update_ink_shadow_visuals()

# ── 视觉搭建（程序化 Control，复用 ChangAnMarket 模式）─────────────

func _build_visuals() -> void:
	world_layer = CanvasLayer.new()
	world_layer.name = "WorldLayer"
	world_layer.layer = 0
	add_child(world_layer)
	move_child(world_layer, 0)

	visual_root = Control.new()
	visual_root.name = "VisualRoot"
	visual_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_layer.add_child(visual_root)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.14, 0.12, 0.18, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(bg)

	# 字母岩壁三层（§5.1）
	_build_letter_wall_layer("UpperWall", Color(0.20, 0.18, 0.26, 1.0), Vector2(360, 80), Vector2(1200, 90), config.get("letter_layers", {}).get("upper", []))
	_build_letter_wall_layer("MiddleWall", Color(0.18, 0.16, 0.22, 1.0), Vector2(240, 200), Vector2(1440, 90), config.get("letter_layers", {}).get("middle", []))
	_build_letter_wall_layer("LowerWall", Color(0.16, 0.14, 0.20, 1.0), Vector2(120, 320), Vector2(1680, 90), config.get("letter_layers", {}).get("lower", []))

	# 中央石碑
	var stele_bg := ColorRect.new()
	stele_bg.name = "SteleBackground"
	stele_bg.color = Color(0.10, 0.09, 0.13, 1.0)
	stele_bg.position = Vector2(660, 460)
	stele_bg.size = Vector2(600, 360)
	stele_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_bg)

	stele_label = Label.new()
	stele_label.name = "SteleLabel"
	stele_label.position = Vector2(660, 480)
	stele_label.size = Vector2(600, 120)
	stele_label.add_theme_font_size_override("font_size", 56)
	stele_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stele_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stele_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_label)

	# 拼写槽位条（§4.5）
	slot_bar = HBoxContainer.new()
	slot_bar.name = "SlotBar"
	slot_bar.position = Vector2(660, 620)
	slot_bar.size = Vector2(600, 80)
	slot_bar.add_theme_constant_override("separation", 12)
	slot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(slot_bar)

	# 词牌架（线索）
	clue_label = Label.new()
	clue_label.name = "ClueLabel"
	clue_label.position = Vector2(120, 460)
	clue_label.size = Vector2(480, 80)
	clue_label.add_theme_font_size_override("font_size", 28)
	clue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(clue_label)

	# 星星条
	star_label = Label.new()
	star_label.name = "StarLabel"
	star_label.position = Vector2(1620, 60)
	star_label.size = Vector2(260, 50)
	star_label.add_theme_font_size_override("font_size", 24)
	star_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	star_label.text = "Stars: 0"
	star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(star_label)

	# 墨影词牌区（§7.5）
	ink_shadow_label = Label.new()
	ink_shadow_label.name = "InkShadowLabel"
	ink_shadow_label.position = Vector2(60, 980)
	ink_shadow_label.size = Vector2(600, 60)
	ink_shadow_label.add_theme_font_size_override("font_size", 20)
	ink_shadow_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.55, 1.0))
	ink_shadow_label.text = "墨影词牌: 0"
	ink_shadow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(ink_shadow_label)

	# 阶段指示
	phase_label = Label.new()
	phase_label.name = "PhaseLabel"
	phase_label.position = Vector2(120, 60)
	phase_label.size = Vector2(480, 50)
	phase_label.add_theme_font_size_override("font_size", 24)
	phase_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 1.0))
	phase_label.text = ""
	phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(phase_label)

func _build_letter_wall_layer(layer_name: String, color: Color, position: Vector2, size: Vector2, letters: Array) -> void:
	var panel := ColorRect.new()
	panel.name = layer_name
	panel.color = color
	panel.position = position
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(panel)
	if letters.is_empty():
		return
	var h_box := HBoxContainer.new()
	h_box.position = Vector2(20, 10)
	h_box.size = Vector2(size.x - 40, size.y - 20)
	h_box.add_theme_constant_override("separation", 16)
	h_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(h_box)
	for letter_value in letters:
		var letter: String = str(letter_value)
		var label := Label.new()
		label.text = letter
		label.custom_minimum_size = Vector2(48, 48)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 32)
		label.add_theme_color_override("font_color", Color(0.9, 0.88, 0.7, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h_box.add_child(label)

func _update_stele_visuals() -> void:
	if stele_label:
		var show_target: bool = bool(config.get("show_target_word_during_reading", false))
		if phase in [Phase.INSCRIBING, Phase.COMPLETE]:
			stele_label.text = str(current_word.get("target", ""))
		elif phase == Phase.READING and show_target:
			stele_label.text = str(current_word.get("target", ""))
		else:
			stele_label.text = ""
	if clue_label:
		var clue: String = str(current_word.get("clue_text", ""))
		clue_label.text = "词牌: %s" % clue

func _update_slot_visuals() -> void:
	if not slot_bar:
		return
	for child in slot_bar.get_children():
		child.queue_free()
	for letter in spelled_letters:
		var slot := Label.new()
		slot.text = letter
		slot.custom_minimum_size = Vector2(48, 60)
		slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot.add_theme_font_size_override("font_size", 40)
		slot.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5, 1.0))
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_bar.add_child(slot)

func _update_ink_shadow_visuals() -> void:
	if ink_shadow_label:
		ink_shadow_label.text = "墨影词牌: %d" % ink_shadow_queue.size()

func _set_quest_text(text: String) -> void:
	if quest_label:
		quest_label.text = text

func _set_phase_text(text: String) -> void:
	if phase_label:
		phase_label.text = text

# ── 对白（复用 ChangAnMarket TTS 模式）─────────────────────────────

func _speak_flow(flow_id: String, lang: String, fallback_seconds: float = 1.8, params: Dictionary = {}) -> void:
	if flow_id.is_empty():
		return
	var merged_params: Dictionary = {"player_name": _player_name()}
	for key in params.keys():
		merged_params[key] = params[key]
	var lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, lang, merged_params)
	if lines.is_empty():
		# 无对白行时等待 fallback
		if fallback_seconds > 0.0:
			await get_tree().create_timer(fallback_seconds).timeout
		return
	if feifei:
		feifei.show_hint(str(lines[0].get("text", "")), FeifeiShoulder.STATE_HINT, 0.0)
	for line in lines:
		var text: String = str(line.get("text", ""))
		var voice: String = str(line.get("voice", "spirit"))
		if text.is_empty():
			continue
		# NPC 语言约束：feifei 可说中文，守灵/Spark 只说英语（§1）
		var speaker: String = str(line.get("speaker", ""))
		var spoken_lang: String = lang
		if speaker != FEIFEI_SPEAKER and spoken_lang == "zh":
			spoken_lang = "en"
			# 重新取英语行
			var en_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, "en", merged_params)
			if not en_lines.is_empty():
				text = str(en_lines[0].get("text", ""))
		await _synthesize_and_wait_for_tts(text, voice, spoken_lang)

func _synthesize_and_wait_for_tts(text: String, voice: String = "spirit", lang: String = "", timeout: float = TTS_PLAYBACK_TIMEOUT) -> bool:
	var audio_manager: Variant = _audio_manager()
	var hybrid_api: Variant = _hybrid_api()
	if not audio_manager or not hybrid_api:
		return false
	var tts_lang: String = lang if not lang.is_empty() else "en"
	var starting_playback_id: int = audio_manager.tts_playback_id
	var state_box := {"finished": false, "duration": 0.0}
	var tts_finished_cb := func(playback_id: int, duration: float):
		if playback_id > starting_playback_id:
			state_box["finished"] = true
			state_box["duration"] = duration
	audio_manager.tts_playback_finished.connect(tts_finished_cb)
	hybrid_api.synthesize_tts(text, voice, tts_lang)
	var elapsed := 0.0
	while not state_box["finished"] and elapsed < timeout:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	if audio_manager.tts_playback_finished.is_connected(tts_finished_cb):
		audio_manager.tts_playback_finished.disconnect(tts_finished_cb)
	if state_box["finished"]:
		await get_tree().create_timer(maxf(TTS_MIC_BUFFER_MIN, float(state_box["duration"]) * 0.05)).timeout
	return bool(state_box["finished"])

# ── 工具 ──────────────────────────────────────────────────────────────

func _normalize_word(text: String) -> String:
	var cleaned: String = text.to_lower().strip_edges()
	var alphabet: String = "abcdefghijklmnopqrstuvwxyz"
	var result: String = ""
	for ch in cleaned:
		if alphabet.find(ch) != -1:
			result += ch
	return result

func _player_name() -> String:
	var manager: Variant = _game_manager()
	if manager and str(manager.player_name) != "":
		return str(manager.player_name)
	return "friend"

func _player_level() -> String:
	var manager: Variant = _game_manager()
	if manager:
		return str(manager.player_cefr_level)
	return "A1"

func _game_manager() -> Variant:
	return get_node_or_null("/root/GameManager")

func _voice_pipeline() -> Variant:
	return get_node_or_null("/root/VoicePipeline")

func _hybrid_api() -> Variant:
	return get_node_or_null("/root/HybridAPI")

func _audio_manager() -> Variant:
	return get_node_or_null("/root/AudioManager")

# ── 配置加载 ──────────────────────────────────────────────────────────

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[WordSpiritLibrary] Failed to load config: %s" % CONFIG_PATH)
		config = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		config = parsed
	else:
		push_error("[WordSpiritLibrary] Config root must be a JSON object.")
		config = {}
