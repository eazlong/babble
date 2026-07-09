## 对话语言系统数据类型定义
##
## 定义对话语言系统所需的所有数据结构：
## - DialogueLine: 预定义对话行（带语言标签）
## - LanguageSegment: 语言分段（用于TTS分段合成）
## - ASRResult: ASR识别结果（含置信度和检测语言）
## - EncouragementTemplate: 鼓励模板（条件匹配 + 响应配置）
## - DialogueSessionState: 对话会话状态（服务端维护，客户端缓存）
##
class_name DialogueTypes
extends RefCounted

# ——— 语言类型枚举 ———
enum Language { ZH, EN, MIXED, UNKNOWN }

static func language_from_string(s: String) -> Language:
	match s.to_lower():
		"zh": return Language.ZH
		"en": return Language.EN
		"mixed": return Language.MIXED
		_: return Language.UNKNOWN

static func language_to_string(lang: Language) -> String:
	match lang:
		Language.ZH: return "zh"
		Language.EN: return "en"
		Language.MIXED: return "mixed"
		_: return "unknown"

# ——— DialogueLine: 预定义对话行 ———
# {
#   "id": "spark_greeting_001",
#   "text": "你好！Hello! 我是Spark。",
#   "language": "mixed",
#   "segments": [{"text": "你好！", "language": "zh"}, ...],
#   "teaching_point": "greeting",
#   "difficulty": "easy"
# }

# ——— LanguageSegment: 语言分段 ———
# {
#   "text": "你好！",
#   "language": "zh"
# }

# ——— ASRResult: ASR识别结果 ———
# {
#   "text": "Good morning",
#   "confidence": 0.85,
#   "detected_language": "en",
#   "processing_time_ms": 1200
# }

# ——— EncouragementTemplate: 鼓励模板 ———
# {
#   "id": "perfect_success",
#   "condition": {
#     "asr_confidence": {"min": 0.9},
#     "detected_language": ["en"]
#   },
#   "priority": 15,
#   "response": {
#     "npc_text": "Excellent! {player_input}! 你说得太棒了！",
#     "spark_action": "celebrate",
#     "difficulty_adjustment": "none",
#     "audio_speed": 1.0
#   },
#   "variants": [...]
# }

# ——— DialogueSessionState: 对话会话状态 ———
# {
#   "session_id": "abc123",
#   "user_id": "user456",
#   "fallback_count": 0,
#   "recent_attempts": [{"success": true, "timestamp": 1234567890}, ...],
#   "scene_id": "spirit_forest",
#   "current_task_id": "watering_tutorial"
# }
