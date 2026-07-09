## 序章场景配置数据（原 SpiritForest 改造）
##
## 三幕序章：
## [1] 破冰与相识 — 小飞猫见面，基础问候，名字收集
## [2] 世界观揭示 — 混沌迷雾讲解，玩家接受主线任务
## [3] 客栈绑定 + 转场 — 引出蜃影客栈，转场长安西市
##
class_name SpiritForestConfig
extends RefCounted

# ——— 步骤枚举 ———
enum Step {
	SPARK_INTRO_NAME,       # 1: 小飞猫飞入 + 基础问候 + 名字收集
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
const SPARK_FLY_IN_DURATION: float = 0.8
const CAMERA_PAN_DURATION: float = 0.8
const SCENE_FADE_DURATION: float = 0.5

# ——— 慢速朗读 ———
const SLOW_READING_WORD_DELAY: float = 0.3

# ——— 相机位置 ———
const CAMERA_DEFAULT_X: float = 0.0

# ——— 小飞猫锚点位置（场景局部坐标） ———
const SPARK_OFFSCREEN_POS: Vector2 = Vector2(2200, 400)
const SPARK_SHOULDER_POS: Vector2 = Vector2(300, 600)
const SPARK_CENTER_POS: Vector2 = Vector2(0, 400)

# ——— 目标场景（序章结束后进入长安西市，暂用 SpiritForestFP 占位）———
const TARGET_SCENE_PATH: String = "res://assets/scenes/ChangAnMarket.tscn"

# ——— 对话文本（中英双语）———
static func get_dialogue(step_key: String, lang: String = "en") -> String:
	var dialogues: Dictionary = {
		# Act 1: 破冰与相识
		"spark_greeting": {
			"en": "Hello! Can you hear me?",
			"zh": "你好！你能听到我吗？"
		},
		"spark_silence_hint": {
			"en": "Try saying Hello to me!",
			"zh": "试着用英语对我说 Hello 吧！"
		},
		"spark_ask_name": {
			"en": "Great! Welcome to the world of Shan Hai Jing! I'm your companion spirit, Xiao Fei Mao. What's your name?",
			"zh": "太棒了！欢迎来到山海经的世界！我是你的伴生精灵小飞猫。你叫什么名字呢？"
		},
		"spark_name_celebrate": {
			"en": "Nice to meet you, %s! I'm so happy to find you here.",
			"zh": "很高兴认识你，%s！能在这里找到你真是太好了。"
		},
		"spark_how_are_you": {
			"en": "Are you okay? You look a little confused.",
			"zh": "你还好吗？你看起来有点迷糊。"
		},
		"spark_okay_response": {
			"en": "Glad to hear that! Let me tell you where we are.",
			"zh": "那就好！让我告诉你我们在哪里。"
		},
		# Act 2: 世界观揭示
		"world_intro_mist": {
			"en": "This place is covered by the Chaos Mist. Long ago, the different tribes stopped talking to each other because they were afraid of being misunderstood.",
			"zh": "这个地方被混沌迷雾笼罩着。很久以前，各个部族因为害怕被误解，互相不再交流。"
		},
		"world_intro_curse": {
			"en": "The mist twists all languages. Friendly greetings sound like angry shouts. The whole world is broken into lonely islands.",
			"zh": "迷雾扭曲了所有的语言。友好的问候听起来像愤怒的叫喊。整个世界四分五裂，变成了互不来往的孤岛。"
		},
		"world_intro_quest": {
			"en": "But your voice is clear! You can break the curse. Will you help me find the six ancient artifacts and save this world?",
			"zh": "但是你的声音是清晰的！你可以打破这个诅咒。你愿意帮我寻找六件上古神器，拯救这个世界吗？"
		},
		"spark_quest_accept_hint": {
			"en": "Say 'Yes, I will!' to accept the quest!",
			"zh": "大声说 'Yes, I will!' 来接受任务吧！"
		},
		"spark_quest_accepted": {
			"en": "Wonderful! Your courage gives me hope!",
			"zh": "太棒了！你的勇气给了我希望！"
		},
		# Act 3: 客栈绑定 + 转场
		"inn_intro": {
			"en": "Look over there! That old tea shed is the ruins of Mirage Inn.",
			"zh": "看那边！那个破旧的茶棚是蜃影客栈的遗址。"
		},
		"inn_intro_history": {
			"en": "Before the curse, it was the busiest place where all tribes gathered to talk. The mist dragon felt your brave voice and gave the inn to you!",
			"zh": "被诅咒之前，这里是各族交流最热闹的地方。蜃龙在梦中感受到了你勇敢的声音，把这个客栈的所有权交给了你！"
		},
		"inn_mechanic_intro": {
			"en": "When we explore outside and make mistakes in speaking, the magic becomes unstable. We can always come back here! If we receive lost guests and practice those wrong sentences, the inn will absorb courage and become more luxurious!",
			"zh": "我们在外面探险时，如果说错了话，魔法就会变得不稳定。这时我们可以随时回到这里！只要接待迷路的客人，重新练习那些说错的话，客栈就会吸收勇气，变得越来越豪华！"
		},
		"inn_first_guest": {
			"en": "Look! Our first guest is here! A merchant blown by the sandstorm. Greet him with 'Hello' and offer him some water!",
			"zh": "看！我们的第一个客人来了！一个被沙暴吹得灰头土脸的商人。用 'Hello' 迎接他，给他倒点水吧！"
		},
		"inn_transition": {
			"en": "Great job! Now let's head to Chang'an Market to find the first artifact — the Donghuang Bell!",
			"zh": "做得好！现在让我们前往长安西市，寻找第一件神器——东皇钟！"
		},
	}

	if dialogues.has(step_key):
		return dialogues[step_key].get(lang, dialogues[step_key].get("en", ""))
	return ""

# ——— 评估类型映射 ———
static func get_assessment_type(step: Step) -> String:
	match step:
		Step.SPARK_INTRO_NAME:
			return "name_collection"
		Step.WORLD_REVEAL:
			return "quest_acceptance"
		_:
			return ""
