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

# ——— 目标场景（序章结束后进入长安西市）———
const TARGET_SCENE_PATH: String = "res://assets/scenes/ChangAnMarket.tscn"

# ——— 对话文本（中英双语）———
static func get_dialogue(step_key: String, lang: String = "en") -> String:
	var dialogues: Dictionary = {
		# Act 1: 破冰与相识
		"feifei_greeting": {
			"en": "Hello, thank goodness you're awake, outsider. I'm feifei. I found you in the Chaos Mist and brought you here. What's your %s name?",
			"zh": "你好啊，太好了，你醒了啊，外来人。我是腓腓。我发现你倒在了混沌迷雾里了，所以把你带到这里来。对了，你叫什么%s名字呀？"
		},
		"feifei_silence_hint": {
			"en": "Try saying Hello to feifei!",
			"zh": "试着用英语对 feifei(腓腓) 说 Hello 吧！"
		},
		"feifei_ask_name": {
			"en": "Great! Welcome to the world of Shan Hai Jing! I'm your companion spirit, feifei. What's your name?",
			"zh": "太棒了！欢迎来到山海经的世界！我是你的伴生精灵 feifei(腓腓)。你叫什么名字呢？"
		},
		"feifei_ask_special_name": {
			"en": "Good, %s is a good name. But people around Mist Island speak in a special language: %s. You need a %s name too. What %s name would you like? Or I can choose one for you.",
			"zh": "好的，%s 是个好名字。不过迷雾岛周围的人们都说话很奇怪，使用了一种特殊的语言，叫%s。你需要有一个%s名字。你可以告诉我你想要的%s名字吗？或者我帮你取一个。"
		},
		"feifei_name_celebrate": {
			"en": "%s sounds wonderful. You must be wondering where this is.",
			"zh": "%s，听起来很棒。我想你应该很好奇这是什么地方。"
		},
		"feifei_how_are_you": {
			"en": "Are you okay? You look a little confused.",
			"zh": "你还好吗？你看起来有点迷糊。"
		},
		"feifei_okay_response": {
			"en": "Glad to hear that! Let me tell you where we are.",
			"zh": "那就好！让我告诉你我们在哪里。"
		},
		# Act 2: 世界观揭示
		"world_intro_mist": {
			"en": "This place is covered by the Chaos Mist. Long ago, the different tribes stopped talking to each other because they were afraid of being misunderstood.",
			"zh": "这个地方被混沌迷雾笼罩着。很久以前，各个部族因为害怕被误解，互相不再交流。"
		},
		"world_intro_mist_island": {
			"en": "This place is called Mist Island. Long ago, it was connected to the outside world. Then the Chaos Mist appeared. It covered the surrounding lands and cut off communication between everyone.",
			"zh": "这里叫做——迷雾岛。很久以前，这里和外面的世界连接在一起。可是不知道什么时候开始，这些混沌迷雾出现了，它覆盖了周围的大陆，也阻断了大家之间的交流。"
		},
		"world_intro_six_continents": {
			"en": "Look, the distant continents are covered by mist. Outside Mist Island, there are six continents. Legend says the power that protects this world comes from six artifacts. But all of them disappeared, and the power guarding Mist Island is growing weaker.",
			"zh": "你看，远方的大陆都被迷雾覆盖了。在迷雾岛外面，还有六块大陆。传说中，保护这个世界的力量来自六件神器。可是不知道为什么，神器全部消失了……现在，守护迷雾岛的力量也越来越弱。"
		},
		"world_intro_curse": {
			"en": "The mist twists all languages. Friendly greetings sound like angry shouts. The whole world is broken into lonely islands.",
			"zh": "迷雾扭曲了所有的语言。友好的问候听起来像愤怒的叫喊。整个世界四分五裂，变成了互不来往的孤岛。"
		},
		"world_intro_quest": {
			"en": "But your voice is clear! You can break the curse. Will you help me find the six ancient artifacts and save this world?",
			"zh": "但是你的声音是清晰的！你可以打破这个诅咒。你愿意帮我寻找六件上古神器，拯救这个世界吗？"
		},
		"feifei_quest_accept_hint": {
			"en": "Say 'Yes, I will!' to accept the quest!",
			"zh": "大声说 'Yes, I will!' 来接受任务吧！"
		},
		"feifei_quest_accepted": {
			"en": "Wonderful! Your courage gives me hope!",
			"zh": "太棒了！你的勇气给了我希望！"
		},
		# Act 3: 客栈绑定 + 转场
		"inn_intro": {
			"en": "Do you see the inn ahead? It is called Mirage Inn. It is the reason this place has no mist. Inside it is a formation powered by the six artifacts, but the artifacts are lost, and the formation is slowly losing its power. Let's go to Mirage Inn. I'll take you there.",
			"zh": "看到前面的客栈了吗？那里叫——蜃影客栈，它就是这里没有迷雾的原因。它内部有一个阵法，阵法能量来源于六个神器，只是神器都遗失了。阵法也逐渐失去它的力量。我们去蜃影客栈看看吧，我带你去。"
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
		"inn_follow_feifei": {
			"en": "Stay close. The mist is quiet here, but we should reach the inn before its light fades.",
			"zh": "跟紧我。这里的迷雾暂时安静，但我们最好在客栈的光弱下去之前进去。"
		},
	}

	if dialogues.has(step_key):
		return dialogues[step_key].get(lang, dialogues[step_key].get("en", ""))
	return ""

# ——— 评估类型映射 ———
static func get_assessment_type(step: Step) -> String:
	match step:
		Step.FEIFEI_INTRO_NAME:
			return "name_collection"
		Step.WORLD_REVEAL:
			return "quest_acceptance"
		_:
			return ""
