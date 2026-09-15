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


## 玩家台词是否表达“继续旅程 / 出发”的意图。
static func matches(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return false
	for marker in MARKERS:
		if normalized.contains(marker.to_lower()):
			return true
	return false
