extends "res://assets/scripts/scenes/BeginningFPController.gd"

## 序章委托识别的测试替身：只保留被测的路由判定与槽位状态机，
## 拦掉一切会走 HTTP（TTS/ASR）、剧情推进与 UI 的方法。
##
## 之所以需要替身而不是直接测控制器：`_propose_special_name` → `_say_text`
## → `_synthesize_and_wait_for_tts` 会等 TTS 播放完成（最长 60s），
## 在无服务/无头环境里会把测试挂死。
##
## 替身**不接进场景树**（控制器的 `@onready` 需要 FeifeiLayer 等整棵场景树），
## 所以这里所有方法都写成同步的——GDScript 允许 `await` 一个非协程调用。
## 若在这里 `await get_tree()...`，因为没有树会直接报 engine error。

var propose_count: int = 0
var handle_name_count: int = 0
var start_listen_count: int = 0
var handled_name: String = ""


func _propose_special_name() -> void:
	propose_count += 1
	# 复刻真实实现的槽位状态迁移（值池挑选 + PROPOSED + 记近期提议），
	# 但不做 TTS/录音。真实实现见 BeginningFPController._propose_special_name。
	var candidate := _pick_special_name_candidate()
	proposed_special_name = candidate
	special_name_slot_state = SLOT_PROPOSED
	if not recent_proposed_special_names.has(candidate):
		recent_proposed_special_names.append(candidate)
	_start_voice_listening()


func _handle_special_name(text: String) -> void:
	handle_name_count += 1
	handled_name = text


func _start_voice_listening(_recording_context: Dictionary = {}) -> void:
	start_listen_count += 1


func _stop_voice_listening() -> void:
	pass


func _loc(_key: String) -> String:
	return ""
