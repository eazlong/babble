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
		assert_false(controller._is_depart_call("画中小世界"), "画卷口令不应触发出发")
		controller.free()


# ── 唤醒词/口令的繁体归一（Whisper 常把普通话输出成繁体）──────────────

func test_depart_matcher_normalizes_traditional_output() -> void:
	var controller = ControllerScript.new()
	# 实测：玩家说「出发！」，whisper 转出的是繁体「出發」——不归一会判否，hub 卡住不出发。
	assert_true(controller._is_depart_call("出發"), "繁体「出發」应被识别为出发口令")
	assert_true(controller._is_depart_call("繼續"), "繁体「繼續」应被识别")
	controller.free()


func test_scroll_matcher_normalizes_traditional_output() -> void:
	var controller = ControllerScript.new()
	# 口令是「画中小世界」：whisper 常把它输出成繁体「畫中小世界」，不归一会判否、卡在这一步。
	assert_true(controller._is_scroll_call("畫中小世界"), "繁体「畫中小世界」（畫→画）应被识别为口令")
	assert_true(controller._is_scroll_call("画中小世界"), "简体口令应被识别")
	assert_true(controller._is_scroll_call("little world in the painting"), "英文口令应被识别")
	assert_false(controller._is_scroll_call("衣橱"), "衣橱不是口令")
	controller.free()


# ── test-audio 模式的答案归属 ─────────────────────────────────────────
#
# 事故复盘：答案顺序原先只写在 project.godot 的全局轮换里。玩家带存档续到本场景时，
# 全局轮换还停在开头，于是「唤醒画卷」这一轮放的是序章的名字答案，孩子怎么说都过不去
# （表现为"说要说出画卷口令时一直不成功"）。修法是让场景自带答案。

func test_intro_and_hub_declare_their_own_test_answers() -> void:
	assert_true(
		ControllerScript.TEST_ASR_INTRO_ANSWERS.size() == 1
		and str(ControllerScript.TEST_ASR_INTRO_ANSWERS[0]).contains("scroll"),
		"导览模式应自带唤醒画卷的答案，实际=%s" % str(ControllerScript.TEST_ASR_INTRO_ANSWERS)
	)
	assert_true(
		ControllerScript.TEST_ASR_HUB_ANSWERS.size() == 1
		and str(ControllerScript.TEST_ASR_HUB_ANSWERS[0]).contains("hub_depart"),
		"hub 模式应自带出发的答案，实际=%s" % str(ControllerScript.TEST_ASR_HUB_ANSWERS)
	)


func test_scene_answer_files_exist_on_disk() -> void:
	for name in (
		ControllerScript.TEST_ASR_INTRO_ANSWERS + ControllerScript.TEST_ASR_HUB_ANSWERS
	):
		var path: String = ControllerScript.TEST_ASR_AUDIO_DIR + str(name)
		assert_true(FileAccess.file_exists(path), "答案音频应存在：%s" % path)

