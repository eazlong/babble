extends Control

## 语音输入指示器（"录音石"）。
##
## 这里原来用的是 80×80 的**麦克风图标**（`ui_mic_button_idle.png`），2026-09-22 换成
## 集气灵石：游戏里"石头在听你说话"这件事只该有一个视觉身份，而序章（BeginningFP）
## 从 T55 起就用灵石做语音按钮了——其余 6 个场景却还在显示麦克风图标，两边不一致。
##
## 现在灵石的五态归本组件管：调用方 `set_state("listening")` 即可，
## 不必各自去 `$Button.texture = ...`（序章那套手写切换保留在它自己控制器里，
## 因为它还要处理"闪一下再回 idle"的时序）。
##
## 贴图缺失时**逐级回退**到旧麦克风图标：美术没导入不该让指示器变成空白方块。

## 状态名 → 灵石贴图。命名与 `BeginningFPController.SPIRIT_STONE` 一致，
## 换图时两边一起换（那边是序章专用，这边是共用默认）。
const STATE_TEXTURES: Dictionary = {
	"idle": "res://assets/textures/ui/spritestone/ui_spirit_stone_idle.png",
	"listening": "res://assets/textures/ui/spritestone/ui_spirit_stone_listening.png",
	"processing": "res://assets/textures/ui/spritestone/ui_spirit_stone_processing.png",
	"success": "res://assets/textures/ui/spritestone/ui_spirit_stone_success.png",
	"hint": "res://assets/textures/ui/spritestone/ui_spirit_stone_hint.png",
}
## 灵石贴图加载不出来时的兜底（旧麦克风图标，仍在仓库里）。
const FALLBACK_IDLE: String = "res://assets/textures/ui/fp/ui_mic_button_idle.png"
const FALLBACK_LISTENING: String = "res://assets/textures/ui/fp/ui_mic_button_recording.png"

## 当前状态名。设置即换图。
var state: String = "idle":
	set(value):
		state = value
		_apply_state()

@onready var button: TextureRect = get_node_or_null("Button")
@onready var pending_upload_badge: Label = get_node_or_null("PendingUploadBadge")

var _texture_cache: Dictionary = {}


func _ready() -> void:
	_apply_state()
	_update_pending_upload_badge()


func _process(_delta: float) -> void:
	_update_pending_upload_badge()


## 切换状态。**必须是方法**而不只是那个属性：调用方要用
## `has_method("set_state")` 做软调用（场景上可能挂着旧版组件，
## 硬调 `mic_button.state = ...` 会在旧组件上直接报错）。
func set_state(state_name: String) -> void:
	state = state_name


func _apply_state() -> void:
	if button == null:
		button = get_node_or_null("Button")
	if button == null:
		return
	var tex: Texture2D = _state_texture(state)
	if tex != null:
		button.texture = tex


func _state_texture(state_name: String) -> Texture2D:
	if _texture_cache.has(state_name):
		return _texture_cache[state_name]
	var tex: Texture2D = _load_first([STATE_TEXTURES.get(state_name, ""), _fallback_for(state_name)])
	_texture_cache[state_name] = tex
	return tex


func _fallback_for(state_name: String) -> String:
	if state_name == "listening":
		return FALLBACK_LISTENING
	if state_name == "idle":
		return FALLBACK_IDLE
	return ""


func _load_first(paths: Array) -> Texture2D:
	for path in paths:
		var p: String = str(path)
		if p.is_empty() or not ResourceLoader.exists(p):
			continue
		var tex: Variant = load(p)
		if tex is Texture2D:
			return tex
	return null


func _update_pending_upload_badge() -> void:
	if pending_upload_badge == null:
		return
	var count := _pending_upload_count()
	pending_upload_badge.visible = count > 0
	pending_upload_badge.text = str(count)


func _pending_upload_count() -> int:
	var magic_echo_manager := get_node_or_null("/root/MagicEchoManager")
	if magic_echo_manager == null or not magic_echo_manager.has_method("get_pending_uploads"):
		return 0
	var uploads: Variant = magic_echo_manager.call("get_pending_uploads")
	if uploads is Array:
		return uploads.size()
	return 0
