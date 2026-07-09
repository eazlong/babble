## 常驻 HUD — 显示玩家进度
##
## 显示：玩家名字、LXP、徽章数、当前任务进度、复习按钮。
## 锚定在屏幕顶部。
##
extends Control

## ============================================================
## Node引用
## ============================================================

@onready var name_label: Label = $NameLabel
@onready var lxp_label: Label = $LXPLabel
@onready var badge_label: Label = $BadgeLabel
@onready var quest_label: Label = $QuestLabel
@onready var quest_progress: TextureProgressBar = $QuestProgress
@onready var review_button: Button = $ReviewButton
@onready var star_progress_bar: ProgressBar = $StarProgressBar  ## 星星条进度

## ============================================================
## 外部系统引用
## ============================================================

var _star_flight_anim: StarFlightAnimation

## ============================================================
## 状态变量
## ============================================================

var current_quest_name: String = ""
var current_quest_progress_val: float = 0.0
var current_quest_total: float = 0.0
var _previous_lxp: int = 0  ## 用于动画

signal review_requested()

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
	# 初始化StarFlightAnimation
	_star_flight_anim = StarFlightAnimation.new()
	add_child(_star_flight_anim)

	visible = false  # 默认隐藏，由 GameManager 控制显示
	_previous_lxp = GameManager.lxp_score
	_update_display()

func show_hud() -> void:
	visible = true
	modulate.a = 0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

func hide_hud() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false)

func _update_display() -> void:
	"""更新 HUD 显示"""
	# 玩家名字
	if name_label:
		var name = GameManager.player_name if GameManager.player_name != "" else "小魔法师"
		name_label.text = name

	# LXP（动画更新）
	var new_lxp = GameManager.lxp_score
	if lxp_label and new_lxp != _previous_lxp:
		_animate_lxp_change(_previous_lxp, new_lxp)
		_previous_lxp = new_lxp
	elif lxp_label:
		lxp_label.text = "⭐ " + str(new_lxp) + " LXP"

	# 星星条进度（动画增长）
	if star_progress_bar:
		var star_value = float(new_lxp)
		_star_flight_anim.animate_star_bar_progress(star_progress_bar,
		                                            star_progress_bar.value,
		                                            star_value)

	# 徽章数
	if badge_label:
		var badge_count = 0
		if "SpellLibrary" in GameManager.unlocked_areas:
			badge_count += 1
		if "RainbowGarden" in GameManager.unlocked_areas:
			badge_count += 1
		# SpiritForest 始终解锁，完成才算 badge
		if GameManager.has_method("get_badge_count"):
			badge_count = GameManager.get_badge_count()
		elif badge_count == 0 and GameManager.unlocked_areas.size() > 1:
			badge_count = GameManager.unlocked_areas.size() - 1
		badge_label.text = "🏅 " + str(badge_count) + "/3"

## ============================================================
## LXP分数变化动画
## ============================================================

func _animate_lxp_change(from_value: int, to_value: int) -> void:
	if not lxp_label:
		return

	# 数字跳动动画
	var tween = lxp_label.create_tween()
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.set_ease(Tween.EASE_OUT)

	# 缩放跳动
	tween.tween_property(lxp_label, "scale", Vector2(1.3, 1.3), 0.2)
	tween.tween_property(lxp_label, "scale", Vector2(1.0, 1.0), 0.3)

	# 数字递增动画（模拟）
	var step_count = 10
	var step_duration = 0.05
	var step_value = (to_value - from_value) / step_count

	for i in range(step_count):
		var display_value = from_value + int(step_value * (i + 1))
		tween.tween_callback(func():
			lxp_label.text = "⭐ " + str(display_value) + " LXP"
		)
		tween.tween_interval(step_duration)

func update_quest(name: String, progress: float, total: float) -> void:
	"""更新任务进度"""
	current_quest_name = name
	current_quest_progress_val = progress
	current_quest_total = total

	if quest_label:
		quest_label.text = name + " (" + str(progress) + "/" + str(total) + ")"

	if quest_progress:
		if total > 0:
			quest_progress.value = (progress / total) * 100.0
		else:
			quest_progress.value = 0

func _on_review_button_pressed() -> void:
	review_requested.emit()
