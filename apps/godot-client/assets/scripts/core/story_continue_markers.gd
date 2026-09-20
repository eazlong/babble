## 旅程续行口令
##
## 蜃影客栈 hub 的「语音出发」与启动时主人房的「继续旅程」共用同一份口令：
## ASR candidate_answers 与本地匹配逻辑都从这里取，避免两处白名单漂移。
class_name StoryContinueMarkers
extends RefCounted

const MARKERS: Array[String] = [
	"let's go", "lets go", "let us go", "let s go",
	"出发", "走吧", "启程", "继续", "接着", "下一课",
	"next lesson", "set off", "go now", "continue", "resume",
]

## 繁体变体 → 简体：Whisper 对普通话口令**经常输出繁体**（实测「出发」→「出發」，
## 「画中小世界」→「畫中小世界」），而口令表只有简体。不归一就会出现"孩子说对了、游戏没听懂"
## —— 与 pypinyin 同音维同类的 ASR 表面形式问题，只能在匹配前归一。
## 只收口令表与客栈唤醒词实际用到的字，不做全量繁简转换。
const TRADITIONAL_VARIANTS: Dictionary = {
	"發": "发", "啟": "启", "繼": "继", "續": "续", "課": "课",
	"書": "书", "閣": "阁", "詞": "词", "靈": "灵", "著": "着",
	"畫": "画",
}


## 把 ASR 可能输出的繁体字归一成简体，便于口令/唤醒词的前缀匹配。
static func normalize_variants(text: String) -> String:
	var result := text
	for traditional in TRADITIONAL_VARIANTS.keys():
		if result.contains(traditional):
			result = result.replace(traditional, TRADITIONAL_VARIANTS[traditional])
	return result


## 玩家台词是否表达“继续旅程 / 出发”的意图。
static func matches(text: String) -> bool:
	var normalized := normalize_variants(text.strip_edges().to_lower())
	if normalized.is_empty():
		return false
	for marker in MARKERS:
		if normalized.contains(marker.to_lower()):
			return true
	return false
