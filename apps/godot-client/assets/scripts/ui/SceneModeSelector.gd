## 场景模式选择器
##
## 玩家点击已完成完成的场景时弹出。
## 提供两种模式：
##   📖 复习模式 — 轻松复习，任务变体
##   🏆 挑战模式 — 限时，双倍奖励
##
extends Control

@export var scene_name: String = ""
@export var scene_display_name: String = ""

@onready var title_label: Label = $TitleLabel
@onready var status_label: Label = $StatusLabel
@onready var review_mode_button: Button = $ReviewModeButton
@onready var challenge_mode_button: Button = $ChallengeModeButton
@onready var spirit_count_label: Label = $SpiritCountLabel

signal mode_selected(mode: String)  # "review" or "challenge"

func _ready() -> void:
	visible = false
	_build_ui()

func _build_ui() -> void:
	"""构建 UI（如果没有预设节点）"""
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		title_label.text = scene_display_name
		title_label.add_theme_font_size_override("font_size", 28)
		add_child(title_label)

	if status_label == null:
		status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.text = ""
		add_child(status_label)

func show_selector(scene_name: String, scene_display: String, is_completed: bool, last_review_time: float, spirit_found: int, spirit_total: int) -> void:
	"""
	显示模式选择器。
	scene_name: 场景内部名称
	scene_display: 显示名称
	is_completed: 是否已完成
	last_review_time: 上次复习的 unix 时间
	spirit_found: 已发现词灵数
	spirit_total: 总词灵数
	"""
	self.scene_name = scene_name
	scene_display_name = scene_display

	if title_label:
		title_label.text = "🌟 " + scene_display

	if status_label:
		var status_parts = []
		if is_completed:
			status_parts.append("✅ 已完成")

		var now = Time.get_unix_time_from_system()
		var hours_since_review = (now - last_review_time) / 3600.0
		if hours_since_review < 1:
			status_parts.append("上次复习: 刚刚")
		elif hours_since_review < 24:
			status_parts.append("上次复习: " + str(int(hours_since_review)) + " 小时前")
		else:
			status_parts.append("上次复习: " + str(int(hours_since_review / 24)) + " 天前")

		status_label.text = " · ".join(status_parts)

	if spirit_count_label:
		spirit_count_label.text = "词灵发现: " + str(spirit_found) + "/" + str(spirit_total) + " 🌟"

	visible = true
	modulate.a = 0
	position.y = -50

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_property(self, "position:y", 0, 0.3)

func hide_selector() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_property(self, "position:y", -50, 0.2)
	tween.tween_callback(func(): visible = false)

func _on_review_mode_pressed() -> void:
	hide_selector()
	mode_selected.emit("review")

func _on_challenge_mode_pressed() -> void:
	hide_selector()
	mode_selected.emit("challenge")

func _on_close_button_pressed() -> void:
	hide_selector()
