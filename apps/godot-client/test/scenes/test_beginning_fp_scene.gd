extends GutTest

const BEGINNING_SCENE_PATH: String = "res://assets/scenes/BeginningFP.tscn"
const INTRO_SCENE_PATH: String = "res://assets/scenes/MirageInnIntroduction.tscn"
const OWNER_ROOM_TEXTURE_SUFFIX: String = "mirage_inn_owner_room_bg.png"

func test_beginning_scene_keeps_controller_nodes_and_owner_room_background() -> void:
	var packed: PackedScene = load(BEGINNING_SCENE_PATH)
	assert_not_null(packed, "BeginningFP.tscn should load")
	var scene: Node = packed.instantiate()
	assert_eq(scene.name, "BeginningFP")
	
	assert_not_null(scene.get_node_or_null("OwnerRoomBackground"), "owner room background should exist")
	assert_not_null(scene.get_node_or_null("InnLayer"), "InnLayer should remain for the magic projection")
	assert_not_null(scene.get_node_or_null("CameraSystem/MainCamera"), "MainCamera should remain")
	assert_not_null(scene.get_node_or_null("HUDLayer/QuestTracker/QuestLabel"), "quest label should remain")
	assert_not_null(scene.get_node_or_null("MicLayer/MicButton"), "mic button should remain")
	assert_not_null(scene.get_node_or_null("FeifeiLayer"), "Feifei layer should remain")
	assert_not_null(scene.get_node_or_null("OverlayLayer"), "overlay layer should remain")
	
	var background: Sprite2D = scene.get_node_or_null("OwnerRoomBackground")
	assert_not_null(background.texture, "owner room background should have a texture")
	assert_true(
		background.texture.resource_path.ends_with(OWNER_ROOM_TEXTURE_SUFFIX),
		"BeginningFP should use the shared owner room background"
	)
	scene.free()

func test_beginning_scene_drops_outdoor_and_legacy_nodes() -> void:
	var packed: PackedScene = load(BEGINNING_SCENE_PATH)
	var scene: Node = packed.instantiate()
	
	assert_null(scene.get_node_or_null("ParallaxBackground"), "outdoor parallax layers should be gone")
	assert_null(scene.get_node_or_null("FeifeiPaths"), "legacy Feifei paths should be gone")
	assert_null(scene.get_node_or_null("CameraSystem/CameraPositions"), "legacy camera markers should be gone")
	assert_null(scene.get_node_or_null("CameraSystem/CameraAnimator"), "legacy camera animator should be gone")
	assert_null(scene.get_node_or_null("FirstPersonNavigator"), "legacy first-person navigator should be gone")
	scene.free()

func test_intro_scene_drops_outdoor_parallax_layers() -> void:
	var packed: PackedScene = load(INTRO_SCENE_PATH)
	assert_not_null(packed, "MirageInnIntroduction.tscn should load")
	var scene: Node = packed.instantiate()
	assert_null(scene.get_node_or_null("ParallaxBackground"), "intro should rely on runtime views instead of outdoor parallax")
	assert_not_null(scene.get_node_or_null("HUDLayer/QuestTracker/QuestLabel"), "intro quest label should remain")
	assert_not_null(scene.get_node_or_null("FeifeiLayer/FeifeiShoulder"), "intro Feifei shoulder should remain")
	scene.free()
