## 序章场景配置数据（原 SpiritForest 改造）
##
## 三幕序章：
## [1] 破冰与相识 — 小飞猫见面，基础问候，名字收集
## [2] 世界观揭示 — 混沌迷雾讲解，玩家接受主线任务
## [3] 客栈绑定 + 转场 — 引出蜃影客栈，转场长安西市
##
class_name BeginningConfig
extends RefCounted

const DialogueFlowLoaderScript = preload("res://assets/scripts/core/dialogue_flow_loader.gd")

# ——— 步骤枚举 ———
enum Step {
	FEIFEI_INTRO_NAME,       # 1: 小飞猫飞入 + 基础问候 + 名字收集
	WORLD_REVEAL,           # 2: 混沌迷雾世界观揭示，玩家接受任务
	INN_BINDING_EXIT        # 3: 蜃影客栈绑定 + 转场长安西市
}

# ——— 星星奖励 ———
const STAR_NAME_COLLECTION: int = 2
const STAR_ACCEPT_QUEST: int = 2
const TOTAL_STARS: int = 4

# ——— 重试与超时 ———
const MAX_ATTEMPTS: int = 3
const SILENCE_TIMEOUT: float = 5.0
const MAX_RECORD_DURATION: float = 10.0

# ——— 动画时长 ———
const FEIFEI_FLY_IN_DURATION: float = 0.8
const CAMERA_PAN_DURATION: float = 0.8
const SCENE_FADE_DURATION: float = 0.5

# ——— 慢速朗读 ———
const SLOW_READING_WORD_DELAY: float = 0.3

# ——— 相机位置 ———
const CAMERA_DEFAULT_X: float = 0.0

# ——— 小飞猫锚点位置（场景局部坐标） ———
const FEIFEI_OFFSCREEN_POS: Vector2 = Vector2(2200, 400)
const FEIFEI_SHOULDER_POS: Vector2 = Vector2(300, 600)
const FEIFEI_CENTER_POS: Vector2 = Vector2(0, 400)

# ——— 目标场景（序章结束后进入蜃影客栈介绍）———
const TARGET_SCENE_PATH: String = "res://assets/scenes/MirageInnIntroduction.tscn"

# ——— 对话文本兼容入口（文本源在 dialogue_flows JSON）———
static func get_dialogue(step_key: String, lang: String = "en", params: Dictionary = {}) -> String:
	var loader: Variant = DialogueFlowLoaderScript.new()
	if not loader.load_dialogue_flows():
		push_warning("[BeginningConfig] Dialogue flow config loaded with errors.")
	return loader.get_text_by_key(step_key, lang, params)

# ——— 评估类型映射 ———
static func get_assessment_type(step: Step) -> String:
	match step:
		Step.FEIFEI_INTRO_NAME:
			return "name_collection"
		Step.WORLD_REVEAL:
			return "quest_acceptance"
		_:
			return ""
