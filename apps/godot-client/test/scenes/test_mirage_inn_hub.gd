extends GutTest

const HUB_SCENE_PATH: String = "res://assets/scenes/MirageInnHub.tscn"
const INTRO_SCENE_PATH: String = "res://assets/scenes/MirageInnIntroduction.tscn"

const ControllerScript = preload("res://assets/scripts/scenes/MirageInnIntroductionController.gd")

func test_hub_scene_instantiates_in_hub_mode() -> void:
	var packed: PackedScene = load(HUB_SCENE_PATH)
	assert_not_null(packed, "MirageInnHub.tscn 应能加载")
	var scene: Node = packed.instantiate()
	assert_eq(scene.name, "MirageInnHub")
	assert_true(bool(scene.hub_mode), "hub 场景应以 hub_mode = true 实例化")
	assert_not_null(scene.get_node_or_null("HUDLayer/QuestTracker/QuestLabel"), "任务栏应在")
	scene.free()

func test_hub_scene_is_registered_in_scene_paths() -> void:
	assert_eq(GameManager.get_scene_path("MirageInnHub"), HUB_SCENE_PATH, "hub 场景应注册在 GameManager.SCENE_PATHS")

func test_intro_scene_defaults_to_intro_mode() -> void:
	var packed: PackedScene = load(INTRO_SCENE_PATH)
	assert_not_null(packed, "MirageInnIntroduction.tscn 应能加载")
	var scene: Node = packed.instantiate()
	assert_false(bool(scene.hub_mode), "序章介绍场景不应是 hub 模式")
	scene.free()

func test_hub_has_no_clickable_depart_button() -> void:
		var file := FileAccess.open("res://assets/scripts/scenes/MirageInnIntroductionController.gd", FileAccess.READ)
		assert_not_null(file, "controller 源码应能读取")
		var source := file.get_as_text()
		assert_false(source.contains("_build_depart_button"), "不应保留点击按钮构建函数")
		assert_false(source.contains("DepartButton"), "不应存在 DepartButton 节点")
		assert_false(source.contains("Button.new()"), "hub 不应创建 Button")
	
func test_hub_scene_file_has_no_button_node() -> void:
	var file := FileAccess.open(HUB_SCENE_PATH, FileAccess.READ)
	assert_not_null(file, "MirageInnHub.tscn 应能读取")
	var text := file.get_as_text()
	assert_false(text.contains("type=\"Button\""), "hub 场景不应有按钮节点")

	var packed: PackedScene = load(HUB_SCENE_PATH)
	var scene: Node = packed.instantiate()
	assert_false(_tree_contains_button(scene), "hub 节点树里不应出现 Button 类型节点")
	scene.free()

func _tree_contains_button(node: Node) -> bool:
	if node is Button:
		return true
	for child in node.get_children():
		if _tree_contains_button(child):
			return true
	return false

func test_depart_voice_matcher_accepts_target_phrases() -> void:
		var controller = ControllerScript.new()
		assert_true(controller._is_depart_call("Let's go!"), "英文出发口令应被识别")
		assert_true(controller._is_depart_call("出发吧"), "中文出发口令应被识别")
		assert_true(controller._is_depart_call("next lesson"), "下一课口令应被识别")
		assert_false(controller._is_depart_call("bookshelf"), "书架口令不应触发出发")
		controller.free()
