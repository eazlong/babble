extends Control
## AchievementPanel — Displays the player's achievement list with progress bars.
## Connects to RewardClient for data.

@onready var achievement_list: VBoxContainer = $MarginContainer/ScrollContainer/AchievementList
@onready var stats_label: Label = $MarginContainer/Header/StatsLabel
@onready var close_button: Button = $MarginContainer/Header/CloseButton

var _user_id: String = ""
var _achievement_items: Array = []

func _ready() -> void:
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	visible = false

	# Connect to RewardClient signals
	var reward_client = get_node_or_null("/root/RewardClient")
	if reward_client:
		reward_client.user_state_updated.connect(_on_user_state_updated)
		reward_client.reward_error.connect(_on_reward_error)

func open(user_id: String) -> void:
	_user_id = user_id
	visible = true
	_fetch_achievements()

func close() -> void:
	visible = false
	_clear_list()

func _fetch_achievements() -> void:
	var reward_client = get_node_or_null("/root/RewardClient")
	if reward_client and _user_id:
		reward_client.get_achievements(_user_id)
		reward_client.get_achievement_stats(_user_id)

func _populate_achievements(data: Dictionary) -> void:
	_clear_list()

	var achievements = data.get("achievements", [])
	var user_progress = data.get("user_progress", [])

	# Build progress lookup
	var progress_map: Dictionary = {}
	for p in user_progress:
		progress_map[p.achievement_id] = p

	for ach in achievements:
		var item = _create_achievement_item(ach, progress_map.get(ach.id, {}))
		achievement_list.add_child(item)
		_achievement_items.append(item)

func _create_achievement_item(ach: Dictionary, progress: Dictionary) -> Control:
	var container = HBoxContainer.new()
	container.custom_minimum_size = Vector2(0, 60)

	# Icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_KEEP_ASPECT
	container.add_child(icon)

	# Text info
	var text_container = VBoxContainer.new()
	text_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label = Label.new()
	name_label.text = ach.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 16)
	text_container.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = ach.get("description", "")
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	text_container.add_child(desc_label)

	container.add_child(text_container)

	# Progress bar / completion
	var progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(100, 16)
	progress_bar.max_value = 1.0

	var prog_value = progress.get("progress", 0.0)
	var is_completed = progress.get("is_completed", false)

	if is_completed:
		progress_bar.value = 1.0
		# Add checkmark
		var check = Label.new()
		check.text = "✓"
		check.add_theme_color_override("font_color", Color.GREEN)
		check.add_theme_font_size_override("font_size", 24)
		container.add_child(check)
	else:
		progress_bar.value = prog_value
		var pct_label = Label.new()
		pct_label.text = str(int(prog_value * 100)) + "%"
		pct_label.custom_minimum_size = Vector2(40, 16)
		container.add_child(pct_label)

	container.add_child(progress_bar)

	return container

func _clear_list() -> void:
	if achievement_list:
		for child in achievement_list.get_children():
			child.queue_free()
	_achievement_items.clear()

func _on_achievements_received(data: Dictionary) -> void:
	_populate_achievements(data)

func _on_stats_received(stats: Dictionary) -> void:
	if stats_label:
		var completed = stats.get("completed", 0)
		var total = stats.get("total", 0)
		stats_label.text = str(completed) + "/" + str(total) + " 成就"

func _on_user_state_updated(_state: Dictionary) -> void:
	# Refresh if panel is open
	if visible:
		_fetch_achievements()

func _on_reward_error(error: String) -> void:
	print("[AchievementPanel] Error: ", error)

func _on_close_pressed() -> void:
	close()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if visible:
			close()
			get_viewport().set_input_as_handled()
