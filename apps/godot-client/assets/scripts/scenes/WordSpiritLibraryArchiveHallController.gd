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
const RenderCapabilitiesScript = preload("res://assets/scripts/core/render_capabilities.gd")

const CONFIG_PATH: String = "res://assets/data/word_spirit_library_scene.json"
const WORD_CARDS_PATH: String = "res://assets/data/word_cards.json"
## 字母精灵组件（v0.3 §5.2.1）。.tscn 缺失时兜底为纯代码构造。
const LETTER_SPIRIT_SCENE: String = "res://assets/scenes/components/LetterSpirit.tscn"
## 组件脚本常量：用 preload 常量做类型标注，不依赖编辑器的全局类缓存
## （无编辑器 headless 环境里 class_name 不会进 global_script_class_cache）。
const LetterSpiritScript = preload("res://assets/scripts/components/LetterSpirit.gd")
const FormationEnergyDialScript = preload("res://assets/scripts/components/FormationEnergyDial.gd")
const SpellingSlotBarScript = preload("res://assets/scripts/components/SpellingSlotBar.gd")
## 共享精灵体贴图。**故意留空是有意为之**：资源不存在时 LetterSpirit 走程序化符文，
## 贴上真美术后零代码改动（见 §5.2.1 第 3 条）。
const SPIRIT_BODY_TEXTURE: String = "res://assets/textures/objects/archive/rune_spirit_body.png"
## 拼写槽位尺寸现在归 `SpellingSlotBar`（`CELL_SIZE` / `CELL_SEPARATION`）——
## 槽位格是组件自己画的，控制器再留一份同样的 48/60/12 只会变成第二个真相源：
## 改一处忘一处，精灵就会飞到格子和格子之间的缝里。需要尺寸时读组件常量。

# ── 版面下移（2026-09-22 用户反馈：字岩壁与能量环重叠）─────────────────
# 阵法能量环常驻屏幕顶部中央（`ENERGY_DIAL_RECT`），而字岩壁原来从 y=80 起，
# 于是三层岩石板从阵盘后面穿出来，字母 K/Q 被压在盘下。
#
# 处理方式：**把除能量环以外的内容统一下移** `CONTENT_SHIFT_Y`。
# 130 = 岩壁原 top(80) → 阵盘底边(202) + 8px 间距。
#
# 为什么不是"只把岩壁下移"：三层岩壁是**独立石板**（板间 30px 缝，见截图），
# 不能叠在一起；三层共需 90*3+30*2 = 330px，而阵盘底边到石碑顶只剩 258px。
# 所以岩壁往下走多少，下面的石碑／槽位条／词牌就得跟着走多少——否则石板会插进石碑。
#
# `CONTENT_SHIFT_Y` 之外**不动**的只有两处，都是有意的：
# - 能量环本身（用户要求它留在顶部）；
# - `ink_shadow_label`（左下角 HUD 读数）：它在 y=980，再下移就出屏（1080）。
#   它和词牌不在同一列（读数文字 x≈60–180，词牌 x 645–1275），所以不冲突。
const CONTENT_SHIFT_Y: float = 130.0
## 能量环控件矩形。它的**底边**（不是画出来的光环底边）是下方内容的让位基准：
## 光环贴图在 200px 控件里实际只画到 y≈179，但换一张更满的底图就会贴到 202，
## 所以这里按控件底边留间距，别按当前贴图的实测值留。
const ENERGY_DIAL_RECT: Rect2 = Rect2(860, 2, 200, 200)

## 字岩壁三层（§5.1）的几何。**这是唯一真相**：`_build_visuals` 与
## `_build_letter_spirits` 都从这里取。从前两处各写一份同样的 Vector2，
## 想整体下移时极容易只改一处，字母精灵就会脱离岩壁。
const WALL_ORIGIN_UPPER: Vector2 = Vector2(360, 80 + CONTENT_SHIFT_Y)
const WALL_ORIGIN_MIDDLE: Vector2 = Vector2(240, 200 + CONTENT_SHIFT_Y)
const WALL_ORIGIN_LOWER: Vector2 = Vector2(120, 320 + CONTENT_SHIFT_Y)
const WALL_SIZE_UPPER: Vector2 = Vector2(1200, 90)
const WALL_SIZE_MIDDLE: Vector2 = Vector2(1440, 90)
const WALL_SIZE_LOWER: Vector2 = Vector2(1680, 90)

## 石碑及其附件的位置基准（原值 + CONTENTS_SHIFT_Y）
const STELE_RECT: Rect2 = Rect2(660, 460 + CONTENT_SHIFT_Y, 600, 360)
const STELE_RING_CENTER: Vector2 = Vector2(960, 640 + CONTENT_SHIFT_Y)
const STELE_LABEL_POSITION: Vector2 = Vector2(660, 480 + CONTENT_SHIFT_Y)
const SLOT_BAR_POSITION: Vector2 = Vector2(660, 620 + CONTENT_SHIFT_Y)

## 词牌（演出拍 9）：720x160 的卷轴卡片，停在石碑正前方
const CARD_SIZE: Vector2 = Vector2(630, 140)
const CARD_REST_POSITION: Vector2 = Vector2(645, 700 + CONTENT_SHIFT_Y)
const CARD_START_POSITION: Vector2 = Vector2(960, 150 + CONTENT_SHIFT_Y)
## 词牌纸面上的字色。**必须跟着词牌底走**，这是本条唯一真正要记住的规则：
## Label 默认字色是白色；线索原来浮在暗色场景上（白色正确），后来挂到词牌卡片上
## （见 GDD §13.6 第 3 批）却没改字色。词牌底换过两次，字色也必须跟着换：
## - 旧底 `ui_scroll_card_bg.png` 是暖白纸面 → 白字等于看不见，当时用暖墨 `Color(0.18,0.14,0.12)`；
## - 现底是 ComfyUI 生成的深靛蓝描金牌面（见 `docs/asset-manifest.md`）→ 暖墨又变成看不见，
##   所以改回暖浅金。
## 换底时先看底是亮是暗，再选这一行的值。
const CARD_TEXT: Color = Color(0.96, 0.92, 0.76, 1.0)
## 唤醒光幕（演出拍 8）
const CURTAIN_SIZE: Vector2 = Vector2(900, 620)
const CURTAIN_CENTER: Vector2 = Vector2(960, 540 + CONTENT_SHIFT_Y)
const WAKE_CURTAIN_MS: int = 1100
const VIEW_SIZE: Vector2 = Vector2(1920, 1080)

# ── 世界层提亮（2026-09-22 用户反馈"整体的颜色偏暗，需要调亮一点"）────────────
# 提亮做成**一层后处理**而不是改美术/改 modulate，理由与做法见 `_build_brightness_pass()`。
# 参数值集中在这里，是为了调"亮到什么程度"时只改一行：
# - `gamma` 抬暗部（提亮的主力）。1.0 = 原样，越大越亮；
# - `gain`  曲线之后的整体增益，1.0 = 不动。实测 1.05 会把高光顶到接近过曝
#           （通道 ≥250 的像素 1.6% → 2.1%），1.0 能拿到同样的暗部提升而不伤高光；
# - `lift`  均匀加常数，会把纯黑洗成灰（发雾），默认 0 不用。
#
# 实测（同一帧开/关对比，整屏平均亮度 /255）：
#   关：mean 41.4、median 28.4、p90 86.4、67% 像素 < 40
#   开：mean 67.3、median ~58、p90 ~123、通道过曝像素 1.7%（关时 1.6%）
const BRIGHTNESS_SHADER: String = "res://assets/resources/shaders/effects/world_brightness.gdshader"
## 提亮层插在**默认画布(0)之上、HUD(10)之下**：
## - 世界美术在 world_layer(-50)，腓腓(FeifeiLayer)是世界空间节点 → 默认画布(0)。
##   两者都是"场景内容"，必须一起提亮；腓腓若被漏掉，会在变亮的背景上变成一个暗块。
## - HUD 10 / dialogue 20 / overlay 30 / mic 90 都在它上面，不受影响（它们本来就够亮）。
## 取 5 而不是 1：给以后可能出现的 layer≤5 的装饰层留出"在提亮之前画"的位置。
const BRIGHTNESS_LAYER: int = 5
const DEFAULT_WORLD_GAMMA: float = 1.5
const DEFAULT_WORLD_GAIN: float = 1.0
const DEFAULT_WORLD_LIFT: float = 0.0

const TTS_PLAYBACK_TIMEOUT: float = 60.0
const TTS_MIC_BUFFER_MIN: float = 0.25
const FEIFEI_SPEAKER: String = "feifei"
const LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

## 共鸣度档位（ADR 0004）：一次"回应"的四种结算形态。
## 每个档位在配置的 star_to_lxp 表里对应一个 LXP，再由 Star Economy §3.1 换算成 1–5★。
const BAND_CLEAR: String = "clear"
const BAND_CLOSE: String = "close"
const BAND_DEMONSTRATION: String = "demonstration"
const BAND_PLAYBACK: String = "playback_review"

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

@onready var feifei: FeifeiBody = get_node_or_null("FeifeiLayer")
## 录音石（VoiceMicIndicator）。听的时候显示 listening 态——
## 灵石有"在听"的贴图（涟漪），直接显 idle 态等于把麦克风的唯一功能丢了。
@onready var mic_button: Control = get_node_or_null("MicLayer/MicButton")
@onready var quest_label: Label = get_node_or_null("HUDLayer/QuestTracker/QuestLabel")

var config: Dictionary = {}
var dialogue_flow_loader: Variant = DialogueFlowLoaderScript.new()
## 词牌线索词表（v0.3 §4.4.1），来自 assets/data/word_cards.json。
var word_cards: Dictionary = {}

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
## 场景提亮后处理：`BRIGHTNESS_LAYER`(5) 层的全屏 ColorRect + ShaderMaterial（见 `_build_brightness_pass()`）。
## 测试从这里拿 material 断言参数，所以两个都留成员变量而不是纯局部。
var brightness_layer: CanvasLayer
var brightness_rect: ColorRect
var stele_label: Label
## 拼写槽位条（场景里的“输入框”）：带待机呼吸与填入光晕的组件。
## 类型写 Control 而不是 class_name：headless 下没有 class_name 缓存，
## 用 preload 常量构造、按 Control 持有（与 FormationEnergyDial 一致）。
var slot_bar: Control
var clue_label: Label
var star_label: Label
var ink_shadow_label: Label
var phase_label: Label
## 阵法能量环（圆形 8 段仪表，取代旧的一行 8 枚平铺光点）。
var formation_dial: Control
## 字母精灵层（v0.3 §5.2.1）：26 个精灵都挂在这一层，**不交给 Container 管位置**——
## HBoxContainer 会覆写子节点 position，精灵就飞不起来了。放在 visual_root 最后 → 动画在最上层。
var spirit_layer: Control
## letter → LetterSpirit（组件，见 LetterSpiritScript 常量）
var letter_spirits: Dictionary = {}
## 槽位字形 Label，按填入顺序（刻印逐字发光要按 index 取）
var slot_labels: Array[Label] = []
## 共享精灵体贴图；为空 → 程序化符文
var spirit_body_texture: Texture2D
## 正在飞向的槽位下标；该槽位此刻不画字形，等精灵落位后再亮起（避免双重描字）
var _flying_slot_index: int = -1
## 阶段焦点高亮（演出拍 4–7）：记录已经应用过的 phase，避免每帧重算
var _focus_phase_applied: int = -1
var _glow_phase: float = 0.0
var _stele_ring_spinning: bool = false
## 石碑朗读光环（READING/JUDGING/INSCRIBING 时亮起）
var stele_glow: TextureRect
## 石碑判读光环（JUDGING 时旋转，其余变暗）
var stele_ring: TextureRect
## 词牌卡片（演出拍 9）；线索 Label 是它的子节点
var word_card: TextureRect
## 唤醒卷轴光幕（演出拍 8）
var wake_curtain: TextureRect
var _card_animating: bool = false
## 光幕是否还在演（演出拍 8）：仪式必须等它收完，否则 feifei 会在光幕上开始说话
var _curtain_animating: bool = false

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
		_show_recording_stone("idle")
		mic_button.visible = false
	call_deferred("_start_scene")
	
	HybridAPI.set_asr_default_answer_test_enabled(true, "res://assets/test_audio/",
		["hello.wav", "letter_a.wav", "letter_p.wav", "letter_p.wav", "letter_l.wav", "letter_e.wav", "done.wav", "apple.wav", "next.wav"])

	# BGM + 环境音（批次 1 T16）：词灵图书馆归档厅——安静神秘 + 聚气室低频嗡鸣
	var audio: Variant = _audio_manager()
	if audio:
		audio.play_bgm_named("res://assets/audio/bgm/archive_hall_bgm.ogg")
		audio.play_ambient_named("res://assets/audio/amb/formation_room_hum.ogg")
	

func _process(delta: float) -> void:
	# 演出拍 4–7（§13.6 第 2 批）：阶段一变化就重算焦点高亮。
	# 用相位检测而不是在每个 phase 赋值点插调用——赋值点有 20 多处，插调用必然漂移。
	if phase != _focus_phase_applied:
		_focus_phase_applied = phase
		_apply_phase_focus()
	_update_stele_aura(delta)
	if _letter_cooldown_timer > 0.0:
		_letter_cooldown_timer -= delta
	if not _voice_listening:
		return
	# 沉默提示（设计文档 §11.2）。沉默不消耗资源，不扣星。
	_silence_timer += delta
	var coach_delay: float = float(config.get("silence_to_coach_prompt_s", 10.0))
	var feifei_delay: float = float(config.get("silence_to_feifei_prompt_s", 15.0))
	var exit_delay: float = float(config.get("silence_to_exit_option_s", 30.0))
	if _silence_timer >= exit_delay:
		_silence_timer = 0.0
		await _speak_flow("archive.guardian_silence_exit_option", "en", 1.5)
	elif _silence_timer >= feifei_delay and phase in [Phase.SPELLING, Phase.READING]:
		_silence_timer = 0.0
		await _speak_flow("archive.feifei_spell_hint" if phase == Phase.SPELLING else "archive.feifei_reading_hint", "en", 1.2)
	elif _silence_timer >= coach_delay:
		_silence_timer = 0.0
		await _speak_flow("archive.feifei_spell_hint" if phase == Phase.SPELLING else "archive.feifei_reading_hint", "en", 1.2)
	
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

## 词牌池生成（v0.3 §9.5）。
## 优先级：1) ink_shadow_queue 回流词（最近失败的排最前，§5.6）
##         2) vocabulary_learned 洗牌补齐
## 60/25/15 的完整调度仍等 summary-service（ADR 0003 第 14 条），本轮不做本地近似。
func _build_word_pool() -> void:
	word_pool.clear()
	_load_word_cards()
	var manager: Variant = _game_manager()
	var learned: Array[String] = []
	if manager:
		for w in manager.vocabulary_learned:
			var word: String = str(w).strip_edges().to_lower()
			if not word.is_empty() and not learned.has(word):
				learned.append(word)
	# learned 为空时用配置里的 fallback 词池，保证场景可玩。
	if learned.is_empty():
		for entry in config.get("fallback_word_pool", []):
			if entry is Dictionary:
				word_pool.append(entry.duplicate(true))
		_slice_pool_for_resume()
		return
	var limit: int = int(config.get("daily_word_cards", 10))
	# 1) 墨影词牌优先回流（§5.6）：队列按失败先后 append，倒序遍历即"最近失败的在前"
	var returning: Array[String] = []
	for i in range(ink_shadow_queue.size() - 1, -1, -1):
		var shadow_id: String = str(ink_shadow_queue[i]).strip_edges().to_lower()
		if shadow_id.is_empty() or returning.has(shadow_id) or not learned.has(shadow_id):
			continue
		returning.append(shadow_id)
	# 2) 剩余名额用洗牌后的已学词补齐；回流词不额外挤占配额，只是先占位
	var rest: Array[String] = learned.duplicate()
	rest.shuffle()
	for shadow_id in returning:
		rest.erase(shadow_id)
	var ordered: Array[String] = returning.duplicate()
	for word_id in rest:
		if ordered.size() >= limit:
			break
		ordered.append(word_id)
	var clue_index: int = 0
	for word_id in ordered.slice(0, limit):
		word_pool.append(_build_word_card(str(word_id), clue_index))
		clue_index += 1
	_slice_pool_for_resume()

## 从存档恢复已完成的词牌索引:词牌池切片为剩余牌后,索引必须归零,
## 否则 _take_next_word_card 用 word_pool[current_word_index] 取牌会双重跳词,
## 且 index >= 切片长度时会误判整个会话已完成。
func _slice_pool_for_resume() -> void:
	if current_word_index > 0 and current_word_index < word_pool.size():
		word_pool = word_pool.slice(current_word_index)
		current_word_index = 0

# ── 词牌线索词表（v0.3 §4.4.1）────────────────────────────────────

## 载入 assets/data/word_cards.json。文件缺失或损坏时不报错：等价于"词表为空"，
## 所有词牌回退成中文释义，场景仍可玩。
func _load_word_cards() -> void:
	word_cards.clear()
	if not FileAccess.file_exists(WORD_CARDS_PATH):
		return
	var file := FileAccess.open(WORD_CARDS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary and parsed.get("words") is Dictionary:
		word_cards = parsed.get("words")

## 按轮换表决定第 index 张词牌用哪类线索，避免整局都是同一种题型。
func _clue_type_for_index(index: int) -> String:
	var rotation: Array = config.get(
		"clue_rotation", ["chinese_meaning", "chinese_meaning", "sentence_gap"]
	)
	if rotation.is_empty():
		return "chinese_meaning"
	return str(rotation[index % rotation.size()])

## 造一张词牌。词表里有该词且该类线索存在 → 用词表线索；否则回退中文释义。
func _build_word_card(word_text: String, index: int) -> Dictionary:
	var word_id: String = word_text.strip_edges().to_lower()
	var card: Dictionary = {
		"word": word_id,
		"target": word_text.strip_edges().to_upper(),
		"clue_type": "chinese_meaning",
		"clue_text": word_text,
		"clue_meaning": "",
	}
	var entry: Variant = word_cards.get(word_id)
	if not (entry is Dictionary):
		return card
	var entry_dict: Dictionary = entry
	card["target"] = str(entry_dict.get("target", card["target"]))
	card["clue_meaning"] = str(entry_dict.get("clue_meaning", ""))
	var clues: Variant = entry_dict.get("clues")
	if not (clues is Dictionary):
		return card
	var clues_dict: Dictionary = clues
	var clue_type: String = _clue_type_for_index(index)
	if clues_dict.has(clue_type):
		card["clue_type"] = clue_type
		card["clue_text"] = str(clues_dict.get(clue_type))
	return card

# ── 取词牌 ────────────────────────────────────────────────────────────

func _take_next_word_card() -> void:
	if current_word_index >= word_pool.size():
		if _formation_energy() < _formation_energy_max():
			_refill_word_pool_for_charge()
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
	# 演出拍 9：词牌飞到石碑前展开，线索随之出现
	await _play_word_card_beat()
	# feifei 首次拼写引导（一次性）
	if not _first_spelling_prompted:
		_first_spelling_prompted = true
		await _speak_flow("archive.feifei_first_spelling", "zh", 1.2)
	else:
		await _speak_flow("archive.feifei_spell_hint", "en", 1.0)
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
		await _speak_flow("archive.feifei_spell_hint", "en", 1.0)
		_start_listening(_build_letter_context())
		return
	# 召唤冷却（设计文档 §5.5），防止连说识别堆积
	if _letter_cooldown_timer > 0.0:
		await _speak_flow("archive.feifei_one_at_a_time", "en", 1.0)
		_start_listening(_build_letter_context())
		return
	_handle_letter_identified(letter, confidence)

func _handle_letter_identified(letter: String, confidence: float) -> void:
	# §9.2：字母识别后落本地记录，供后续校准 letter_high/medium_threshold（§13.3）
	_record_letter_recognition(letter, confidence)
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
	await _speak_flow("archive.feifei_letter_unclear", "en", 1.0)
	_start_listening(_build_letter_context())

func _adopt_letter(letter: String) -> void:
	spelled_letters.append(letter)
	_letter_cooldown_timer = float(config.get("letter_summon_cooldown_ms", 600)) / 1000.0
	_confirm_letter = ""
	_confirm_count = 0
	# 演出拍 1：召唤亮起 → 弧线飞入槽位（不 await，动画不阻塞 ASR）
	_play_letter_summon(letter, spelled_letters.size() - 1)
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
			await _speak_flow("archive.feifei_spell_hint", "en", 1.0)
			_start_listening(_build_letter_context())

func _undo_last_letter() -> void:
	if spelled_letters.is_empty():
		_start_listening(_build_letter_context())
		return
	var undone: String = spelled_letters[spelled_letters.size() - 1]
	spelled_letters.pop_back()
	_return_spirit_home(undone)
	if not _first_undo_prompted:
		_first_undo_prompted = true
		await _speak_flow("archive.feifei_first_undo", "zh", 1.2)
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _clear_letters() -> void:
	spelled_letters.clear()
	_return_all_spirits_home()
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _remove_letter(letter: String) -> void:
	for i in range(spelled_letters.size() - 1, -1, -1):
		if spelled_letters[i] == letter:
			spelled_letters.remove_at(i)
			_return_spirit_home(letter)
			break
	_update_slot_visuals()
	_start_listening(_build_letter_context())

func _confirm_spell() -> void:
	phase = Phase.SPELL_CONFIRM
	_stop_listening()
	# 演出拍 10（§13.6 第 3 批）：槽位条整体发光——"整行都在等判读"
	_pulse_slot_bar()
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
	await _speak_flow("archive.feifei_spell_error", "en", 1.2)
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
		await _speak_flow("archive.feifei_reading_hint", "en", 1.0)
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
			_inscribe_word(BAND_CLEAR)
		elif confidence >= 0.65:
			_inscribe_word(BAND_CLOSE)
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
	await _speak_flow("archive.feifei_reading_retry", "en", 1.2)
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
			# 回放自评接受 → LXP 50 → 2★（ADR 0004）
			_inscribe_word(BAND_PLAYBACK)
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

func _inscribe_word(band: String) -> void:
	phase = Phase.INSCRIBING
	_stop_listening()
	# 示范模式兜底：无论本次识别多好，都按 demonstration 档结算并封顶（§7.4 / ADR 0004）
	if demo_mode_active:
		band = BAND_DEMONSTRATION
	var stars: int = _stars_for_band(band)
	var lxp: int = int(config.get("star_to_lxp", {}).get(band, 0))
	_grant_stars(stars, lxp)
	stars_this_session += stars
	inscribed_count += 1
	_rest_card_counter += 1
	# 刻印成功 = 该词走到终点：从墨影队列移除（§5.6 第 3 条）+ 记掌握度增量（§9.2）
	_clear_from_ink_shadow(str(current_word.get("word", "")))
	_record_mastery_delta(0.1)
	_update_stele_visuals()
	_update_star_visuals()
	# 演出拍 2：铭文逐字刻入（§13.6 第 1 批）
	await _play_inscribe_beat()
	# 刻印成功表现（§7.1）。5 星制下 4★ 及以上算"说清楚了"
	var flow_id: String = "archive.feifei_inscribe_clear" if stars >= 4 else "archive.feifei_inscribe_close"
	await _speak_flow(flow_id, "en", 1.2)
	if _apply_review_unit_energy():
		await _complete_formation_charge()
		return
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
	var shadow_word: String = str(current_word.get("word", ""))
	# §5.6：同一张词牌只进队列一次，避免重复失败把队列刷满同义词
	if not shadow_word.is_empty() and not ink_shadow_queue.has(shadow_word):
		ink_shadow_queue.append(shadow_word)
	# §9.2：墨影生成时写 error_record
	_record_error(shadow_word, "reading_attempts_exhausted")
	# 演出拍 3：散落抛物线回位（轻柔，不是错误蜂鸣 §7.2）
	await _play_scatter_beat()
	if ink_shadow_queue.size() > int(config.get("ink_shadow_soft_cap", 5)):
		await _speak_flow("archive.feifei_too_many_ink_shadow", "zh", 1.8)
	elif consecutive_ink_shadow >= 2:
		await _speak_flow("archive.feifei_consecutive_ink_shadow", "zh", 1.5)
	else:
		await _speak_flow("archive.feifei_scatter", "en", 1.2)
	_update_ink_shadow_visuals()
	if _apply_review_unit_energy():
		await _complete_formation_charge()
		return
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
	await _speak_flow("archive.feifei_demo_intro", "en", 1.2)
	# 逐字母点亮目标单词的字母精灵并播放字母名发音（演出拍 11，§13.6 第 3 批）
	var target: String = str(current_word.get("target", ""))
	for i in range(target.length()):
		var letter: String = target[i]
		var lit: LetterSpiritScript = _spirit_for(letter)
		if lit != null:
			lit.play_summon_flash()
		await get_tree().create_timer(float(config.get("demo_letter_lit_s", 0.4))).timeout
		# TTS 播放字母名，并等它真的念完再念下一个
		_speak_letter_name(letter)
		await _await_tts_or_timeout(float(config.get("demo_letter_tts_s", 0.5)))
	await _speak_flow("archive.feifei_demo_outro", "en", 1.0)
	# 示范读完，点亮的精灵回岩壁（字形随之落到槽位里，不需要它们继续站在上面）
	for i in range(target.length()):
		_return_spirit_home(target[i])
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
	if _formation_energy() >= _formation_energy_max():
		_exit_scene()
		return
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
	var hub_path: String = GameManager.get_scene_path("MirageInnHub")
	if hub_path.is_empty():
		hub_path = "res://assets/scenes/MainMenu.tscn"
	get_tree().change_scene_to_file(hub_path)

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
		_show_recording_stone("listening")
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.start_listening(recording_context)

func _stop_listening() -> void:
	_voice_listening = false
	_silence_timer = 0.0
	if mic_button:
		_show_recording_stone("idle")
		mic_button.visible = false
	var voice_pipeline: Variant = _voice_pipeline()
	if voice_pipeline:
		voice_pipeline.stop_listening()

## 切录音石的状态。组件缺失/无此方法时静默跳过（贴图回退由组件自己负责）。
func _show_recording_stone(state_name: String) -> void:
	if mic_button and mic_button.has_method("set_state"):
		mic_button.set_state(state_name)


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
	# 演出拍 8：卷轴光幕 + 符文依次现身——这是"守灵醒了"唯一的视觉证据
	await _play_wake_ritual()
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

# ── 星辉发放（ADR 0004）────────────────────────────────────────────

## 共鸣度档位 → LXP → 星辉。LXP 取值来自配置 star_to_lxp，不硬编码。
func _stars_for_band(band: String) -> int:
	var table: Dictionary = config.get("star_to_lxp", {})
	var lxp: int = int(table.get(band, 0)) if table is Dictionary else 0
	var stars: int = _stars_per_response(lxp)
	if band == BAND_DEMONSTRATION:
		stars = mini(stars, int(config.get("demonstration_star_cap", 3)))
	return stars

## Star Economy GDD §3.1 的固定五档表。
## 返回 0 表示"没有有效回应"（再试 / 机会耗尽），不发星——但也不扣分。
func _stars_per_response(lxp_score: int) -> int:
	if lxp_score >= 90:
		return 5
	if lxp_score >= 75:
		return 4
	if lxp_score >= 60:
		return 3
	if lxp_score >= 40:
		return 2
	if lxp_score > 0:
		return 1
	return 0

## 星辉进钱包、LXP 进学习分。两者不再互相反推（v0.3 删除了 star_to_lxp_multiplier）。
func _grant_stars(star_count: int, lxp_score: int = 0) -> void:
	var manager: Variant = _game_manager()
	if manager == null:
		return
	if star_count > 0 and manager.has_method("add_stars"):
		manager.add_stars(star_count)
	if lxp_score > 0:
		manager.lxp_score += lxp_score

## 星辉条只反映本局累计，从 stars_this_session 派生（CLAUDE.md §12：UI 不维护自己的计数）。
func _update_star_visuals() -> void:
	if star_label:
		star_label.text = "Stars: %d" % stars_this_session

# ── 本地学习记录（v0.3 §9.2 / §9.5：只落客户端，不上报）──────────────

func _record_letter_recognition(letter: String, confidence: float) -> void:
	var manager: Variant = _game_manager()
	if manager and manager.has_method("record_letter_recognition"):
		manager.record_letter_recognition(str(current_word.get("word", "")), letter, confidence)

func _record_error(word_id: String, error_type: String) -> void:
	var manager: Variant = _game_manager()
	if manager and manager.has_method("record_error"):
		manager.record_error(word_id, error_type)

func _record_mastery_delta(delta: float) -> void:
	var manager: Variant = _game_manager()
	if manager and manager.has_method("record_mastery_update"):
		manager.record_mastery_update(str(current_word.get("word", "")), delta)

## 刻印成功 → 该词从墨影重试队列出列（§5.6 第 3 条）。
func _clear_from_ink_shadow(word_id: String) -> void:
	if word_id.is_empty():
		return
	var changed: bool = false
	while ink_shadow_queue.has(word_id):
		ink_shadow_queue.erase(word_id)
		changed = true
	if changed:
		_update_ink_shadow_visuals()

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
	# 读档恢复：直接落到当前格数，不播点亮演出（否则一进场就白爆一次光）。
	_update_formation_energy_visuals(false)

# ── 视觉搭建（程序化 Control，复用 ChangAnMarket 模式）─────────────

## 世界层提亮（2026-09-22 用户反馈"整体的颜色偏暗"）。
##
## 场景美术本身偏暗：实测整屏平均亮度 42.9/255，62% 的像素低于 40。这里在场景内容之上
## 插一层全屏后处理，用 gamma 曲线把暗部抬起来（见 `world_brightness.gdshader` 注释里
## 为什么不用乘法）。
##
## **层级是关键**：pass 放在 `BRIGHTNESS_LAYER`(5) —— 世界是 -50、腓腓在默认画布(0)，
## 两者都算"场景内容"要被提亮；HUD 10 / dialogue 20 / overlay 30 / mic 90 都在它上面，
## 不受影响（它们本来就够亮，再抬一次会过曝）。
##
## 参数走场景 JSON（`world_gamma` / `world_gain` / `world_lift`），和本场景其他调参一致；
## 缺省时用 1.5 / 1.05 / 0，即"明显变亮但不发灰"。
func _build_brightness_pass() -> void:
	if brightness_layer != null:
		return
	brightness_layer = CanvasLayer.new()
	brightness_layer.name = "BrightnessLayer"
	brightness_layer.layer = BRIGHTNESS_LAYER
	add_child(brightness_layer)
	var mat := _make_brightness_material()
	if mat == null:
		# headless（Dummy 渲染器）不支持 shader：只留一个空层，什么都别画。
		# **绝不能**在没有材质的情况下放 ColorRect：它的默认色是不透明白，会糊满整屏。
		return
	# 取屏幕纹理前必须先给本帧的场景内容"拍一张"：BackBufferCopy 排在 ColorRect 之前，
	# 把世界 + 腓腓所在的画面拷进 backbuffer，ColorRect 才能读到"提亮前的场景"。
	# 少了它，shader 采到的是自己刚写回去的内容 → 逐帧自乘的反馈回路，几帧内烧成纯白。
	var snapshot := BackBufferCopy.new()
	snapshot.name = "ScreenSnapshot"
	snapshot.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	brightness_layer.add_child(snapshot)
	var rect := ColorRect.new()
	rect.name = "WorldBrightness"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	# `rect.color` 保持默认的**不透明白**，别改成透明：片元输出会被这个 modulate 乘一遍，
	# alpha 设为 0 会让整层彻底看不见（提亮静默失效，参数怎么调都没反应）。
	# 也正因为如此，没拿到材质时不能建这个矩形。
	brightness_layer.add_child(rect)
	brightness_rect = rect


## 提亮参数（纯函数，便于 headless 测试）：JSON 配了就用 JSON，否则用常量缺省。
func _brightness_params() -> Dictionary:
	return {
		"gamma_lift": float(config.get("world_gamma", DEFAULT_WORLD_GAMMA)),
		"gain": float(config.get("world_gain", DEFAULT_WORLD_GAIN)),
		"lift": float(config.get("world_lift", DEFAULT_WORLD_LIFT)),
	}


func _make_brightness_material() -> ShaderMaterial:
	if not _shaders_supported():
		return null
	if not ResourceLoader.exists(BRIGHTNESS_SHADER):
		return null
	var shader: Shader = load(BRIGHTNESS_SHADER) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var params: Dictionary = _brightness_params()
	for key: String in params:
		mat.set_shader_parameter(key, params[key])
	return mat


## headless（Dummy 渲染器）不支持 shader，挂材质会 push 引擎错误 → GUT 判失败
## （详见 `render_capabilities.gd`：本场景曾因此一次红 107 个用例）。
## 判定收在 RenderCapabilities 里，序章的睁眼过场用的是同一句。
static func _shaders_supported() -> bool:
	return RenderCapabilitiesScript.supports_shaders()


func _build_visuals() -> void:
	world_layer = CanvasLayer.new()
	world_layer.name = "WorldLayer"
	# T6 修正：场景美术建在 CanvasLayer 里，layer=0 时 Godot 会把它绘制在**默认画布之上**，
	# 从而盖住世界空间的 FeifeiBody（迁移后腓腓是世界空间节点，不再像旧的 FeifeiShoulder 那样
	# 自己在 CanvasLayer(20) 里）。取 -50：仍在 ParallaxBackground(-100) 之上，但在默认画布(0)
	# 与所有 UI(HUD 10 / dialogue 20 / overlay 30 / mic 90) 之下，层级恢复正常。
	world_layer.layer = -50
	add_child(world_layer)
	move_child(world_layer, 0)

	_build_brightness_pass()

	visual_root = Control.new()
	visual_root.name = "VisualRoot"
	visual_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_layer.add_child(visual_root)

	# T39: 真实背景（Agnes 生成 → 1920x1080），cover 式铺满
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = load("res://assets/textures/backgrounds/archive_hall_bg.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(bg)

	# 字母岩壁三层（§5.1）— T40: 真实字岩壁纹理（1 生成→3 裁），字母 Label 仍叠于其上
	# 位置取自 WALL_ORIGIN_*（已含 CONTENT_SHIFT_Y），与 _build_letter_spirits 同源
	_build_letter_wall_layer("UpperWall", Color(0.20, 0.18, 0.26, 1.0), WALL_ORIGIN_UPPER, WALL_SIZE_UPPER, config.get("letter_layers", {}).get("upper", []), "res://assets/textures/backgrounds/archive_letter_wall_upper.png")
	_build_letter_wall_layer("MiddleWall", Color(0.18, 0.16, 0.22, 1.0), WALL_ORIGIN_MIDDLE, WALL_SIZE_MIDDLE, config.get("letter_layers", {}).get("middle", []), "res://assets/textures/backgrounds/archive_letter_wall_middle.png")
	_build_letter_wall_layer("LowerWall", Color(0.16, 0.14, 0.20, 1.0), WALL_ORIGIN_LOWER, WALL_SIZE_LOWER, config.get("letter_layers", {}).get("lower", []), "res://assets/textures/backgrounds/archive_letter_wall_lower.png")

	# 中央石碑 — T41: 真实石碑纹理（600x360，5:3 中心裁）
	var stele_bg := TextureRect.new()
	stele_bg.name = "SteleBackground"
	stele_bg.texture = load("res://assets/textures/backgrounds/archive_stele_bg.png")
	stele_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stele_bg.stretch_mode = TextureRect.STRETCH_SCALE
	stele_bg.position = STELE_RECT.position
	stele_bg.size = STELE_RECT.size
	stele_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_bg)

	# 石碑朗读光环 + 判读光环（演出拍 4–7）：放在石碑底板之上、铭文之下
	stele_glow = TextureRect.new()
	stele_glow.name = "SteleGlow"
	stele_glow.texture = load("res://assets/textures/objects/inn/word_spirit_glow.png")
	stele_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stele_glow.stretch_mode = TextureRect.STRETCH_SCALE
	stele_glow.position = STELE_RECT.position
	stele_glow.size = STELE_RECT.size
	stele_glow.modulate = Color(1, 1, 1, 0)
	stele_glow.visible = false
	stele_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_glow)

	stele_ring = TextureRect.new()
	stele_ring.name = "SteleRing"
	stele_ring.texture = load("res://assets/textures/objects/inn/formation_ring.png")
	stele_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stele_ring.stretch_mode = TextureRect.STRETCH_SCALE
	stele_ring.size = Vector2(420, 420)
	stele_ring.position = STELE_RING_CENTER - stele_ring.size * 0.5
	stele_ring.pivot_offset = stele_ring.size * 0.5
	stele_ring.visible = false
	stele_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_ring)

	stele_label = Label.new()
	stele_label.name = "SteleLabel"
	stele_label.position = STELE_LABEL_POSITION
	stele_label.size = Vector2(600, 120)
	stele_label.add_theme_font_size_override("font_size", 56)
	stele_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stele_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stele_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(stele_label)

	# 拼写槽位条（§4.5）
	# T42: 玉金槽框（Pillow 合成 600x80），槽字母叠于其上
	var slot_frame := TextureRect.new()
	slot_frame.name = "SlotFrame"
	slot_frame.texture = load("res://assets/textures/ui/archive_slot_frame.png")
	slot_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	slot_frame.stretch_mode = TextureRect.STRETCH_SCALE
	slot_frame.position = SLOT_BAR_POSITION
	slot_frame.size = Vector2(600, 80)
	slot_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(slot_frame)
	slot_bar = SpellingSlotBarScript.new()
	slot_bar.name = "SlotBar"
	slot_bar.position = SLOT_BAR_POSITION
	slot_bar.size = Vector2(600, 80)
	slot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(slot_bar)

	# 词牌架（线索）
	# 词牌（演出拍 9）：**线索长在词牌上**。原来线索是浮在左边的独立 Label，
	# 看起来像调试信息而不是"词牌"；现在词牌飞到石碑前展开，线索随之出现。
	word_card = TextureRect.new()
	word_card.name = "WordCard"
	word_card.texture = load("res://assets/textures/ui/ui_scroll_card_bg.png")
	word_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	word_card.stretch_mode = TextureRect.STRETCH_SCALE
	word_card.size = CARD_SIZE
	word_card.position = CARD_REST_POSITION
	word_card.pivot_offset = CARD_SIZE * 0.5
	word_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(word_card)

	clue_label = Label.new()
	clue_label.name = "ClueLabel"
	clue_label.position = Vector2(40, 24)
	clue_label.size = CARD_SIZE - Vector2(80, 48)
	clue_label.add_theme_font_size_override("font_size", 30)
	clue_label.add_theme_color_override("font_color", CARD_TEXT)
	clue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	word_card.add_child(clue_label)

	# 星星条
	star_label = Label.new()
	star_label.name = "StarLabel"
	star_label.position = Vector2(1620, 60 + CONTENT_SHIFT_Y)
	star_label.size = Vector2(260, 50)
	star_label.add_theme_font_size_override("font_size", 24)
	star_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	star_label.text = "Stars: 0"
	star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(star_label)
	# Formation energy progress (ADR 0003 #12：0–8 格充能)。
	# 旧版是「一行 8 枚平铺光点 + 文字」，读起来像进度条，不像"法阵在蓄能"；
	# 换成 FormationEnergyDial（环形 8 段弧 + 自转阵纹 + N/8 读数），
	# 位置沿用原来那一带的视觉中心，少遮挡上层墙面。
	formation_dial = FormationEnergyDialScript.new()
	formation_dial.name = "FormationEnergyDial"
	# 能量环是**唯一不下移**的一层（用户要求它留在顶部），所以它的矩形
	# 同时是下方内容的让位基准，见 ENERGY_DIAL_RECT。
	formation_dial.position = ENERGY_DIAL_RECT.position
	formation_dial.size = ENERGY_DIAL_RECT.size
	# 说明文字交给组件自己排在盘心深色底里：在场景里另摆一个 Label 的话，
	# 它的落点会跟着阵盘尺寸变，很容易飘到金色阵纹带上（见 GDD §7.6）。
	formation_dial.caption = "阵法能量"
	visual_root.add_child(formation_dial)

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
	phase_label.position = Vector2(120, 60 + CONTENT_SHIFT_Y)
	phase_label.size = Vector2(480, 50)
	phase_label.add_theme_font_size_override("font_size", 24)
	phase_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9, 1.0))
	phase_label.text = ""
	phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(phase_label)

	# 卷轴光幕（演出拍 8）：唤醒守灵的一瞬从中心纵向摊开，摊开即淡出（是"开门"，不是遮挡）
	wake_curtain = TextureRect.new()
	wake_curtain.name = "WakeCurtain"
	wake_curtain.texture = load("res://assets/textures/ui/ui_scroll_panel_bg.png")
	wake_curtain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wake_curtain.stretch_mode = TextureRect.STRETCH_SCALE
	wake_curtain.size = CURTAIN_SIZE
	wake_curtain.position = CURTAIN_CENTER - CURTAIN_SIZE * 0.5
	wake_curtain.pivot_offset = CURTAIN_SIZE * 0.5
	wake_curtain.visible = false
	wake_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(wake_curtain)

	# 字母精灵层（v0.3 §5.2.1）：最后加入 → 精灵与飞行动画绘制在所有面板之上
	spirit_layer = Control.new()
	spirit_layer.name = "SpiritLayer"
	spirit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	spirit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(spirit_layer)
	_build_letter_spirits()

func _build_letter_wall_layer(layer_name: String, color: Color, position: Vector2, size: Vector2, letters: Array, tex_path: String = "") -> void:
	# T40: 有纹理时画 TextureRect，否则回退纯色 ColorRect
	var panel: Control
	if tex_path != "":
		var tr := TextureRect.new()
		tr.texture = load(tex_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		panel = tr
	else:
		var cr := ColorRect.new()
		cr.color = color
		panel = cr
	panel.name = layer_name
	panel.position = position
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual_root.add_child(panel)
	# v0.3：字母不再由这里的 HBoxContainer 承载——字母精灵住在 spirit_layer，
	# 位置自己算（Container 会覆写 position，精灵就飞不起来）。这里只留岩壁底板。

# ── 字母精灵（v0.3 §5.2.1 / §5.3）────────────────────────────────────

## 造 26 个字母精灵：共享同一张精灵体，靠叠在精灵体上的字形区分 A–Z。
## 重复字母（apple 的两个 P）不克隆新精灵，而是同一精灵连飞两次——时序上不会重叠。
func _build_letter_spirits() -> void:
	if spirit_layer == null:
		return
	for child in spirit_layer.get_children():
		child.queue_free()
	letter_spirits.clear()
	spirit_body_texture = _load_spirit_body_texture()
	var layers: Dictionary = config.get("letter_layers", {})
	# origin/size 取自 WALL_ORIGIN_* / WALL_SIZE_*，与 _build_visuals 里的岩壁底板同源：
	# 两处各写一份常量的话，整体下移时只改一处，精灵就会整层脱离岩壁。
	var wall_specs: Array[Dictionary] = [
		{"letters": layers.get("upper", []), "origin": WALL_ORIGIN_UPPER, "size": WALL_SIZE_UPPER},
		{"letters": layers.get("middle", []), "origin": WALL_ORIGIN_MIDDLE, "size": WALL_SIZE_MIDDLE},
		{"letters": layers.get("lower", []), "origin": WALL_ORIGIN_LOWER, "size": WALL_SIZE_LOWER},
	]
	for spec in wall_specs:
		var letters: Array = spec["letters"]
		for i in range(letters.size()):
			var letter: String = str(letters[i])
			var spirit: LetterSpiritScript = _instantiate_letter_spirit()
			if spirit == null:
				continue
			spirit.name = "Spirit_%s" % letter
			spirit_layer.add_child(spirit)
			spirit.setup(letter, spirit_body_texture)
			spirit.settle_at_home(
				_letter_home_position(spec["origin"], spec["size"], i, letters.size())
			)
			# 演出拍 8：刚进归卷厅时 26 个符文都在沉睡，唤醒守灵后才依次浮现
			spirit.set_revealed(false)
			letter_spirits[letter] = spirit

## .tscn 优先（美术可以在编辑器里改组件），缺失时兜底为纯代码构造。
func _instantiate_letter_spirit() -> LetterSpiritScript:
	if ResourceLoader.exists(LETTER_SPIRIT_SCENE):
		var packed: Variant = load(LETTER_SPIRIT_SCENE)
		if packed is PackedScene:
			var node: Node = packed.instantiate()
			if node is LetterSpiritScript:
				return node
			if node != null:
				node.free()
	return LetterSpiritScript.new()

## 精灵体贴图；资源尚未导入（真美术还没落地）时返回 null → 程序化符文。
func _load_spirit_body_texture() -> Texture2D:
	if not ResourceLoader.exists(SPIRIT_BODY_TEXTURE):
		return null
	var tex: Variant = load(SPIRIT_BODY_TEXTURE)
	return tex as Texture2D

## 岩壁原位：字母**均匀铺满**整块岩壁。
## 原来的 HBoxContainer 是左对齐挤在左边（1680 宽的岩壁只用到 576），看起来不像"字岩壁"。
func _letter_home_position(
	origin: Vector2, wall_size: Vector2, index: int, count: int
) -> Vector2:
	var half: Vector2 = LetterSpiritScript.DEFAULT_SIZE * 0.5
	var y: float = origin.y + wall_size.y * 0.5 - half.y
	if count <= 1:
		return Vector2(origin.x + wall_size.x * 0.5 - half.x, y)
	var margin: float = 60.0
	var step: float = (wall_size.x - margin * 2.0) / float(count - 1)
	return Vector2(origin.x + margin + step * float(index) - half.x, y)

func _spirit_for(letter: String) -> LetterSpiritScript:
	var key: String = letter.strip_edges().to_upper()
	if key.is_empty():
		return null
	var value: Variant = letter_spirits.get(key)
	if value == null or not is_instance_valid(value):
		return null
	return value as LetterSpiritScript

## 第 index 个拼写槽位的中心。**位置由组件的 `get_cell_center()` 给出**——
## 槽位格是居中排布的（4 字词和 8 字词都居中），所以不能再按"左排 + index×间距"算，
## 否则精灵会飞到画面之外的空气里。
func _slot_center(index: int) -> Vector2:
	if slot_bar == null or spirit_layer == null:
		return Vector2.ZERO
	# 用局部坐标换算，避免依赖两层祖先是否恰好无变换
	var bar_origin: Vector2 = slot_bar.global_position
	if slot_bar.is_inside_tree() and spirit_layer.is_inside_tree():
		bar_origin = spirit_layer.get_global_transform().affine_inverse() * slot_bar.global_position
	if not slot_bar.has_method("get_cell_center"):
		return bar_origin
	return bar_origin + (slot_bar.get_cell_center(index) as Vector2)

# ── 演出拍 1：召唤 → 弧线飞入槽位 → 融入槽位（§13.6 第 1 批）────────

## 不 await：飞行动画绝不能阻塞 ASR 流程（说下一个字母时上一只还在飞是允许的）。
func _play_letter_summon(letter: String, slot_index: int) -> void:
	var spirit: LetterSpiritScript = _spirit_for(letter)
	if spirit == null:
		return
	spirit.kill_action()
	spirit.play_summon_flash()
	if not spirit.flight_finished.is_connected(_on_spirit_slotted):
		spirit.flight_finished.connect(_on_spirit_slotted)
	_flying_slot_index = slot_index
	spirit.fly_to(_slot_center(slot_index), int(config.get("letter_fly_duration_ms", 350)))

## 精灵落位 → 槽位字形亮起 + 精灵融入字形（槽位条负责显字，避免双重描字）。
func _on_spirit_slotted(spirit_letter: String) -> void:
	# 先记下落点：下面会把 _flying_slot_index 清掉，但"点亮哪一格"要用它。
	var landed_index: int = _flying_slot_index
	_flying_slot_index = -1
	var spirit: LetterSpiritScript = _spirit_for(spirit_letter)
	if spirit != null:
		spirit.merge_into_slot()
	_update_slot_visuals()
	# 填入演出：落到哪一格就点亮哪一格（字形弹入 + 该格光晕）。
	# 这是"字母进去了"的正反馈，和不填时的空槽呼吸形成对照。
	if landed_index >= 0 and slot_bar != null:
		slot_bar.play_land(landed_index)

## 撤回 / 清空 / 移除：让对应精灵直接回到岩壁原位（不飞，避免和玩家下一句话抢注意力）。
func _return_spirit_home(letter: String) -> void:
	var spirit: LetterSpiritScript = _spirit_for(letter)
	if spirit == null:
		return
	spirit.kill_action()
	spirit.settle_at_home(spirit.home_position)

func _return_all_spirits_home() -> void:
	for key in letter_spirits.keys():
		_return_spirit_home(str(key))

# ── 演出拍 8：唤醒守灵（§13.6 第 3 批）─────────────────────────────

## 卷轴光幕 + 26 个符文依次现身。
## 在此之前归卷厅是"睡着的"：符文 alpha 为 0（见 _build_letter_spirits）。
## 守灵被唤醒这件事必须有可见的因果，否则玩家不知道自己的话起了作用。
func _play_wake_ritual() -> void:
	_play_wake_curtain()
	var layers: Dictionary = config.get("letter_layers", {})
	var reveal_ms: int = int(config.get("rune_reveal_ms", 260))
	var stagger_ms: int = int(config.get("rune_reveal_stagger_ms", 40))
	var revealed: Array = []
	for layer_key in ["upper", "middle", "lower"]:
		for letter_value in layers.get(layer_key, []):
			var spirit: LetterSpiritScript = _spirit_for(str(letter_value))
			if spirit == null:
				continue
			spirit.play_reveal(reveal_ms)
			revealed.append(spirit)
			if revealed.size() < 26:
				await get_tree().create_timer(float(stagger_ms) / 1000.0).timeout
	# 等符文现身**和**光幕都收完：光幕还在演就往下走的话，
	# feifei 会在光幕上开始说话、词牌会叠在光幕上飞进来。
	var curtain_ms: int = int(config.get("wake_curtain_ms", WAKE_CURTAIN_MS))
	await _await_until(
		func() -> bool: return not _curtain_animating and not _any_spirit_animating(revealed),
		maxi(reveal_ms + 500, curtain_ms + 400)
	)
	# 现身完再按当前阶段铺一次焦点（沉睡期间 set_focus 被组件挡住）
	_apply_phase_focus()

## 光幕从中心纵向摊开、摊开即淡出——是"开门"的一瞬，不是遮挡层。
func _play_wake_curtain() -> void:
	if wake_curtain == null:
		return
	wake_curtain.visible = true
	wake_curtain.position = CURTAIN_CENTER - CURTAIN_SIZE * 0.5
	wake_curtain.pivot_offset = CURTAIN_SIZE * 0.5
	wake_curtain.scale = Vector2(1.0, 0.04)
	wake_curtain.modulate = Color(1, 1, 1, 0.0)
	if not wake_curtain.is_inside_tree():
		wake_curtain.visible = false
		return
	var total: float = maxf(float(config.get("wake_curtain_ms", WAKE_CURTAIN_MS)), 1.0) / 1000.0
	_curtain_animating = true
	var tween: Tween = wake_curtain.create_tween()
	tween.tween_property(wake_curtain, "modulate", Color(1, 1, 1, 0.85), total * 0.16)
	tween.parallel().tween_property(wake_curtain, "scale", Vector2.ONE, total * 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(wake_curtain, "modulate", Color(1, 1, 1, 0.0), total * 0.32)
	tween.tween_callback(func() -> void:
		wake_curtain.visible = false
		_curtain_animating = false
	)

# ── 演出拍 9：取词牌（§13.6 第 3 批）───────────────────────────────

## 词牌从岩壁上方飞到石碑前展开。
## "展开"= scale.x 从 0.08 拉到 1（横向像卷轴摊开）+ 淡入 + 落位回弹。
## 线索文案写在牌面上（clue_label 是 word_card 的子节点），牌落定即线索出现。
func _play_word_card_beat() -> void:
	if word_card == null:
		return
	word_card.visible = true
	word_card.position = CARD_START_POSITION
	word_card.scale = Vector2(0.08, 1.0)
	word_card.modulate = Color(1, 1, 1, 0)
	if not word_card.is_inside_tree():
		word_card.position = CARD_REST_POSITION
		word_card.scale = Vector2.ONE
		word_card.modulate = Color(1, 1, 1, 1)
		return
	var duration: float = maxf(float(config.get("card_fly_duration_ms", 600)), 1.0) / 1000.0
	_card_animating = true
	var tween: Tween = word_card.create_tween()
	tween.tween_property(word_card, "position", CARD_REST_POSITION, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(word_card, "scale", Vector2(1.06, 1.0), duration * 0.85)
	tween.parallel().tween_property(word_card, "modulate", Color(1, 1, 1, 1), duration * 0.6)
	tween.tween_property(word_card, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	tween.tween_callback(func() -> void: _card_animating = false)
	await _await_until(func() -> bool: return not _card_animating, int(duration * 1000.0) + 400)

# ── 演出拍 4–7：阶段焦点高亮（§13.6 第 2 批）────────────────────────

## 纯语音输入下，玩家没有鼠标可以示意"我在看什么"——画面焦点是唯一的视觉路标（§4.5）。
## 每个阶段回答同一个问题："现在该对谁说话？"
func _apply_phase_focus() -> void:
	var wall_focus: float = 1.0
	var glow_on: bool = false
	var ring_spinning: bool = false
	match phase:
		Phase.SPELLING, Phase.SPELL_CONFIRM:
			# 该说字母名了 → 岩壁泛光，石碑退后
			wall_focus = 1.18
		Phase.READING:
			# 该朗读了 → 岩壁退到背景，石碑亮起朗读光环
			wall_focus = 0.45
			glow_on = true
		Phase.JUDGING:
			# 判读中 → 光环旋转，其余变暗
			wall_focus = 0.35
			glow_on = true
			ring_spinning = true
		Phase.INSCRIBING:
			wall_focus = 0.6
			glow_on = true
		Phase.SCATTERING:
			wall_focus = 0.5
		_:
			wall_focus = 1.0
	for key in letter_spirits.keys():
		var spirit: LetterSpiritScript = _spirit_for(str(key))
		if spirit != null:
			spirit.set_focus(wall_focus)
	_stele_ring_spinning = ring_spinning
	if stele_glow != null:
		stele_glow.visible = glow_on
	if stele_ring != null:
		stele_ring.visible = ring_spinning

## 光环呼吸 + 旋转。只改视觉，不碰状态机（CLAUDE.md §12：UI 只反映状态）。
func _update_stele_aura(delta: float) -> void:
	if stele_glow != null and stele_glow.visible:
		_glow_phase += delta
		var pulse: float = 0.55 + 0.25 * sin(_glow_phase * 3.0)
		stele_glow.modulate = Color(1.0, 1.0, 1.0, pulse)
	if stele_ring != null and stele_ring.visible and _stele_ring_spinning:
		stele_ring.rotation_degrees = fmod(stele_ring.rotation_degrees + delta * 60.0, 360.0)

# ── 演出拍 2：铭文逐字刻入（§13.6 第 1 批）──────────────────────────

## 逐字点亮石碑铭文 + 对应槽位脉冲。总时长 = 字数 × inscribe_char_delay_ms。
func _play_inscribe_beat() -> void:
	var target: String = str(current_word.get("target", ""))
	if target.is_empty() or phase == Phase.EXITING:
		return
	var delay_s: float = maxf(float(config.get("inscribe_char_delay_ms", 80)), 1.0) / 1000.0
	if stele_label:
		stele_label.text = ""
	for i in range(target.length()):
		if stele_label:
			stele_label.text = target.substr(0, i + 1)
		if i < slot_labels.size():
			slot_bar.play_land(i)
		await get_tree().create_timer(delay_s).timeout
	if stele_label:
		stele_label.text = target

## 念一个字母名。抽成方法是为了给测试留出口（避免测试真发 TTS 请求）。
func _speak_letter_name(letter: String) -> void:
	var api: Variant = _hybrid_api()
	if api:
		api.synthesize_tts(letter, "spirit", "en")

## 等 TTS 真的念完，最多等 max_wait_s。
## 不这样做的话示范会连发请求：HTTPRequest 忙 → 请求被丢 → 这个字母**没被念出来**，
## 而示范模式的全部意义就是让玩家听到字母名（§7.4）。
## 用"信号 + 帧轮询 + 上界"而不是裸等信号：念不动时也不能把示范卡住。
func _await_tts_or_timeout(max_wait_s: float) -> void:
	var audio: Variant = get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_signal("tts_playback_finished"):
		await get_tree().create_timer(max_wait_s).timeout
		return
	var finished: bool = false
	var on_finished := func(_playback_id: int = 0, _duration: float = 0.0) -> void:
		finished = true
	audio.tts_playback_finished.connect(on_finished)
	var deadline: int = Time.get_ticks_msec() + int(maxf(max_wait_s, 0.0) * 1000.0)
	while not finished and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if audio.tts_playback_finished.is_connected(on_finished):
		audio.tts_playback_finished.disconnect(on_finished)

## 演出拍 10（§13.6 第 3 批）：整条槽位条发光，表示"整行都在等判读"。
func _pulse_slot_bar() -> void:
	if slot_bar == null or not slot_bar.is_inside_tree():
		return
	slot_bar.pivot_offset = slot_bar.size * 0.5
	var tween: Tween = slot_bar.create_tween()
	tween.tween_property(slot_bar, "modulate", Color(1.35, 1.28, 1.02, 1.0), 0.12)
	tween.tween_property(slot_bar, "modulate", Color(1, 1, 1, 1), 0.22)

# ── 演出拍 3：散落抛物线回位（§13.6 第 1 批）────────────────────────

## 墨影词牌：拼错的字母精灵从槽位抛物散去、回岩壁原位。轻柔，不是错误蜂鸣（§7.2）。
func _play_scatter_beat() -> void:
	var duration_ms: int = int(config.get("scatter_fly_duration_ms", 500))
	var departing: Array[String] = []
	for letter in spelled_letters:
		departing.append(letter)
	# 先撤掉槽位字形，让精灵"从槽位起飞"而不是凭空出现
	spelled_letters.clear()
	_flying_slot_index = -1
	_update_slot_visuals()
	var index: int = 0
	var flying: Array = []
	for letter in departing:
		var spirit: LetterSpiritScript = _spirit_for(letter)
		if spirit != null:
			spirit.kill_action()
			spirit.position = _slot_center(index) - spirit.size * 0.5
			spirit.scatter_home(duration_ms, 70.0)
			flying.append(spirit)
		index += 1
	await _await_spirits_settled(flying, duration_ms)

## 等一个条件成立，最多等 timeout_ms。
## 表现层的 Tween 一旦因节点离树而停住，剧情流程不能跟着卡死——所以一律"帧轮询 + 上界"，
## 既不裸等 Tween.finished / 信号，也不等"和动画等长的 timer"（那是竞态，见 §13.6.1）。
func _await_until(condition: Callable, timeout_ms: int) -> void:
	var deadline: int = Time.get_ticks_msec() + maxi(timeout_ms, 1)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return
		await get_tree().process_frame

func _any_spirit_still_scattering(spirits: Array) -> bool:
	for spirit in spirits:
		if is_instance_valid(spirit) and spirit.state == LetterSpiritScript.State.SCATTERING:
			return true
	return false

func _any_spirit_animating(spirits: Array) -> bool:
	for spirit in spirits:
		if is_instance_valid(spirit) and spirit.is_animating:
			return true
	return false

## 等所有精灵真正落位（不是等一个等长的 timer）。
func _await_spirits_settled(spirits: Array, duration_ms: int) -> void:
	if spirits.is_empty():
		return
	await _await_until(
		func() -> bool: return not _any_spirit_still_scattering(spirits), duration_ms + 300
	)

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
		# §4.4.1：sentence_gap 显示带空槽的例句 + 中文兜底线索；chinese_meaning 直接显示释义
		var clue: String = str(current_word.get("clue_text", ""))
		var clue_type: String = str(current_word.get("clue_type", "chinese_meaning"))
		var meaning: String = str(current_word.get("clue_meaning", ""))
		# 线索长在词牌卡片上（演出拍 9），不再重复写"词牌:"前缀
		if clue_type == "sentence_gap":
			var hint: String = "（%s）" % meaning if not meaning.is_empty() else ""
			clue_label.text = "%s %s" % [clue, hint]
		else:
			clue_label.text = clue

func _update_slot_visuals() -> void:
	if not slot_bar:
		return
	# 槽位数 = 目标单词长度（开局就摆出 N 个空槽，孩子能看出要拼几个字母）。
	# 还没取到词牌时（current_word 为空：单元测试、词表加载失败）回退成"已拼字母数"，
	# 槽位条不会因为一个空 current_word 就整条消失。
	# 下界取 spelled_letters.size()：万一词牌比已拼的还短（换词／异常），
	# 也不能把已经拼进去的字母挤掉。
	var target_len: int = str(current_word.get("target", "")).length()
	var count: int = target_len if target_len > 0 else spelled_letters.size()
	count = clampi(maxi(count, spelled_letters.size()), 0, SpellingSlotBarScript.MAX_CELLS)
	slot_bar.cell_count = count
	slot_labels.clear()
	for i in range(count):
		var glyph: Label = slot_bar.get_glyph_label(i)
		if glyph == null:
			continue
		if i < spelled_letters.size():
			# 正飞向这个槽位的精灵还没落位 → 先不画字形，等 _on_spirit_slotted 亮起
			slot_bar.set_glyph(i, "" if i == _flying_slot_index else spelled_letters[i])
		else:
			slot_bar.set_glyph(i, "")
		slot_labels.append(glyph)

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
		feifei.show_hint(str(lines[0].get("text", "")), FeifeiBody.STATE_HINT, 0.0)
	for line in lines:
		var text: String = str(line.get("text", ""))
		var voice: String = str(line.get("voice", "spirit"))
		if text.is_empty():
			continue
		# NPC 语言约束：feifei 可说中文，守灵等 NPC 只说英语（§1）
		var speaker: String = str(line.get("speaker", ""))
		var spoken_lang: String = lang
		if speaker != FEIFEI_SPEAKER and spoken_lang == "zh":
			spoken_lang = "en"
			# 重新取英语行
			var en_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, "en", merged_params)
			if not en_lines.is_empty():
				text = str(en_lines[0].get("text", ""))
		# TTS 播报态：飞飞音（spirit）时口型循环；其他 voice 停口型。气泡在循环前已显示，这里不动。
		var feifei_speaking: bool = voice == "spirit"
		if feifei:
			if feifei_speaking:
				feifei.talk_speaking_start()
			else:
				feifei.talk_speaking_end()
		await _synthesize_and_wait_for_tts(text, voice, spoken_lang)
		if feifei and feifei_speaking:
			feifei.talk_speaking_end()

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


func _formation_energy() -> int:
	var manager: Variant = _game_manager()
	if manager and manager.has_method("get_formation_energy"):
		return int(manager.get_formation_energy())
	return 0

func _formation_energy_max() -> int:
	var manager: Variant = _game_manager()
	if manager and manager.has_method("get_formation_energy_max"):
		return int(manager.get_formation_energy_max())
	return 8

func _apply_review_unit_energy() -> bool:
	var manager: Variant = _game_manager()
	if not manager or not manager.has_method("add_formation_energy"):
		return false
	if manager.get_formation_energy() >= manager.get_formation_energy_max():
		return false
	var completed: bool = manager.add_formation_energy(1)
	_update_formation_energy_visuals()
	return completed

func _complete_formation_charge() -> void:
	phase = Phase.COMPLETE
	_stop_listening()
	_set_quest_text(_localized_flow_text("archive.formation_charge_full"))
	_set_phase_text("Charge complete")
	await _speak_flow("archive.formation_charge_full", "zh", 1.8)
	current_word_index = 0
	_save_progress()
	_exit_scene()

func _refill_word_pool_for_charge() -> void:
	current_word_index = 0
	word_pool.clear()
	_build_word_pool()

func _localized_flow_text(flow_id: String) -> String:
	var lang: String = "zh"
	var manager: Variant = _game_manager()
	if manager:
		lang = str(manager.SOURCE_LANGUAGE_CODE)
	var flow_lines: Array[Dictionary] = dialogue_flow_loader.get_lines(flow_id, lang)
	if flow_lines.is_empty():
		return ""
	return str(flow_lines[0].get("text", ""))

## 把 GameManager 的阵法能量推进到环上。数字只在这里读，组件本身不碰存档
## （CLAUDE.md §12：UI 只反映状态）。
func _update_formation_energy_visuals(animate: bool = true) -> void:
	var energy := _formation_energy()
	var max_energy := _formation_energy_max()
	if formation_dial and formation_dial.has_method("set_energy"):
		formation_dial.set_energy(energy, max_energy, animate)
