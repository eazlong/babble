## NPC 额外对话管理
##
## 管理 L2 NPC 额外对话池。
## 玩家点击/靠近 NPC 时，按次数返回不同的对话内容。
## 同时支持基于任务阶段的上下文对话。
##
extends Node

class_name NPCExtraDialogue

# ——— 对话条目 ———
class DialogueEntry:
	var id: String
	var text_zh: String
	var text_en: String
	var keywords: Array[String] = []  # 关联的词灵关键词
	var trigger_context: String = ""  # 触发上下文（如 "color_task_before"）
	var spirit_hint: String = ""  # 词灵预告

# ——— 内部状态 ———
var _dialogue_pool: Array[DialogueEntry] = []
var _current_index: int = 0
var _click_count: int = 0
var _last_said_id: String = ""

signal extra_dialogue_shown(entry: DialogueEntry)

# ——— 初始化 ———

func set_dialogues(entries: Array[DialogueEntry]) -> void:
	"""设置对话池"""
	_dialogue_pool = entries.duplicate()
	_current_index = 0
	_click_count = 0

func add_dialogue(entry: DialogueEntry) -> void:
	"""添加单条对话"""
	_dialogue_pool.append(entry)

# ——— 外部接口 ———

func get_next_dialogue(context_tag: String = "") -> DialogueEntry:
	"""
	获取下一条对话。
	context_tag: 当前任务阶段标签（如 "color_task_before"）。
	优先返回匹配上下文的对话。
	"""
	_click_count += 1

	# 1. 优先匹配上下文对话
	if not context_tag.is_empty():
		for entry in _dialogue_pool:
			if entry.trigger_context == context_tag and entry.id != _last_said_id:
				_last_said_id = entry.id
				extra_dialogue_shown.emit(entry)
				return entry

	# 2. 按顺序返回常规对话
	if _dialogue_pool.is_empty():
		return _create_fallback()

	# 循环遍历对话池
	var start_index = _current_index
	for i in range(_dialogue_pool.size()):
		var idx = (_current_index + i) % _dialogue_pool.size()
		var entry = _dialogue_pool[idx]

		# 跳过有上下文限制的条目（除非当前上下文匹配）
		if not entry.trigger_context.is_empty() and entry.trigger_context != context_tag:
			continue

		# 避免重复
		if entry.id == _last_said_id:
			continue

		_current_index = (idx + 1) % _dialogue_pool.size()
		_last_said_id = entry.id
		extra_dialogue_shown.emit(entry)
		return entry

	# 如果所有对话都已说完，返回最后一条
	var fallback = _dialogue_pool[(_current_index - 1 + _dialogue_pool.size()) % _dialogue_pool.size()]
	extra_dialogue_shown.emit(fallback)
	return fallback

func get_click_count() -> int:
	return _click_count

func reset() -> void:
	_current_index = 0
	_click_count = 0
	_last_said_id = ""

# ——— 便利工厂方法 ———

static func create_entry(id: String, zh: String, en: String, keywords: Array[String] = [], context: String = "", spirit: String = "") -> DialogueEntry:
	var entry = DialogueEntry.new()
	entry.id = id
	entry.text_zh = zh
	entry.text_en = en
	entry.keywords = keywords
	entry.trigger_context = context
	entry.spirit_hint = spirit
	return entry

# ——— 各场景预设对话池 ———

static func get_oakley_dialogues() -> Array[DialogueEntry]:
	return [
		create_entry("oakley_1",
			"嗯……每一朵花都有自己的名字。",
			"Hmm... Every flower has its own name.",
			["flower", "name"], "color_task_before", "light"),
		create_entry("oakley_2",
			"数字是魔法世界里最古老的咒语。",
			"Numbers are the oldest magic spells.",
			["number", "ancient", "spell"], "number_task_before", ""),
		create_entry("oakley_3",
			"嗯……慢慢来。Try again, little one. 不着急。",
			"Hmm... Take your time. Try again, little one.",
			["try", "patience"], "", ""),
		create_entry("oakley_4",
			"这片森林已经等了你很久很久……",
			"This forest has been waiting for you for a very long time...",
			["wait", "long time", "friend"], "", ""),
		create_entry("oakley_5",
			"你已经是一个真正的森林之友了。",
			"You are a true friend of the forest now.",
			["friend", "forest", "belong"], "after_badge", ""),
	]

static func get_bookmark_dialogues() -> Array[DialogueEntry]:
	return [
		create_entry("bookmark_1",
			"这本书记载着颜色的魔法……",
			"This book contains the magic of colors...",
			["book", "color", "magic"], "organize_before", "book"),
		create_entry("bookmark_2",
			"嘘……有些书在睡觉，不要吵醒它们。",
			"Shh... Some books are sleeping. Don't wake them.",
			["sleep", "quiet", "book"], "", ""),
		create_entry("bookmark_3",
			"我曾经认识一个比你更调皮的小魔法师……",
			"I once knew a little mage even naughtier than you...",
			["once", "little mage", "naughty"], "", ""),
		create_entry("bookmark_4",
			"图书馆的秘密：最强大的魔法书，是一本空白的书。",
			"The library's secret: the most powerful book is a blank one.",
			["secret", "blank book", "write"], "", "star"),
		create_entry("bookmark_5",
			"慢慢来……知识不会跑掉。",
			"Take your time... Knowledge never runs away.",
			["take your time", "knowledge", "stay"], "", ""),
	]

static func get_luna_dialogues() -> Array[DialogueEntry]:
	return [
		create_entry("luna_1",
			"你觉得哪本书最有趣？",
			"Which book do you think is the most interesting?",
			["interesting", "book", "favorite"], "dialogue_before", ""),
		create_entry("luna_2",
			"哇你比我快多了！教教我！",
			"Wow, you're so much faster than me! Teach me!",
			["fast", "teach me", "amazing"], "after_organize", ""),
		create_entry("luna_3",
			"哈哈我也这么觉得！我们真有默契！",
			"Haha, I think so too! We're on the same page!",
			["same", "like", "together"], "", "dream"),
		create_entry("luna_4",
			"跟你说真开心！下次再来聊！",
			"It's so fun talking to you! Let's chat again!",
			["fun", "talk", "again"], "dialogue_after", ""),
	]

static func get_petalialogues() -> Array[DialogueEntry]:
	return [
		create_entry("petalia_1",
			"每一朵花都有自己的名字和故事。",
			"Every flower has its own name and story.",
			["flower", "name", "story"], "garden_entry", ""),
		create_entry("petalia_2",
			"你闻到了吗？这是快乐的味道。",
			"Can you smell it? That's the scent of happiness.",
			["smell", "happy", "sweet"], "", ""),
		create_entry("petalia_3",
			"蝴蝶是我的朋友，它们会告诉我你的事。",
			"Butterflies are my friends. They tell me about you.",
			["butterfly", "friend", "tell"], "", ""),
		create_entry("petalia_4",
			"花园最美的不是花，是来看花的人。",
			"The most beautiful thing in the garden isn't the flowers, it's the visitors.",
			["beautiful", "you", "smile"], "", "love"),
		create_entry("petalia_5",
			"你是花园最受欢迎的小魔法师。",
			"You are the most welcome little mage in the garden.",
			["welcome", "garden", "special"], "", ""),
	]

static func get_sunny_dialogues() -> Array[DialogueEntry]:
	return [
		create_entry("sunny_1",
			"有了你，天气每天都开开心心的！",
			"Because of you, the weather is happy every day!",
			["happy weather", "every day"], "after_weather", ""),
		create_entry("sunny_2",
			"小动物们说谢谢你！",
			"The animals say thank you!",
			["animals", "thank you", "happy"], "after_animals", ""),
		create_entry("sunny_3",
			"你想明天出太阳还是下雨？",
			"Do you want it sunny or rainy tomorrow?",
			["tomorrow", "sunny", "rainy"], "", ""),
	]

static func get_feifei_dialogues() -> Array[DialogueEntry]:
	return [
		create_entry("feifei_1",
			"森林里有好多神奇的植物！",
			"There are so many magical plants in the forest!",
			["forest", "plants", "magical"], "", ""),
		create_entry("feifei_2",
			"你听到鸟叫声了吗？那是词灵鸟在唱歌！",
			"Do you hear the birds? That's the Word Spirit bird singing!",
			["bird", "sing", "song"], "", "bird"),
		create_entry("feifei_3",
			"试试跟蘑菇说话，它们有时候会回答哦！",
			"Try talking to the mushrooms, sometimes they answer!",
			["mushroom", "talk", "answer"], "", ""),
		create_entry("feifei_4",
			"你看！树叶上写着英文字母！",
			"Look! The leaves have English letters on them!",
			["leaf", "letter", "write"], "", ""),
		create_entry("feifei_5",
			"这片森林已经等了你很久很久……",
			"This forest has been waiting for you for a very long time...",
			["wait", "long time", "friend"], "", ""),
	]

# ——— Fallback ———

func _create_fallback() -> DialogueEntry:
	var entry = DialogueEntry.new()
	entry.id = "fallback"
	entry.text_zh = "✨"
	entry.text_en = "✨"
	return entry
