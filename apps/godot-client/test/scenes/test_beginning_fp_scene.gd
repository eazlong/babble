extends GutTest

const BEGINNING_SCENE_PATH: String = "res://assets/scenes/BeginningFP.tscn"
const INTRO_SCENE_PATH: String = "res://assets/scenes/MirageInnIntroduction.tscn"
## The owner-room background is split into three layers (2026-09-23): the room
## plate (lantern and scroll painted out) plus the two hanging elements, which sit
## at their original crop origins so the stacked result is the approved flat art.
const OWNER_ROOM_LAYERS: Dictionary = {
	"OwnerRoomBackground": "mirage_inn_owner_room_layer_plate.png",
	"OwnerRoomScroll": "mirage_inn_owner_room_layer_scroll.png",
	"OwnerRoomLantern": "mirage_inn_owner_room_layer_lantern.png",
}
const OWNER_ROOM_LAYER_ORIGINS: Dictionary = {
	"OwnerRoomBackground": Vector2(0, 0),
	"OwnerRoomScroll": Vector2(832, 192),
	"OwnerRoomLantern": Vector2(896, 0),
}

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
		background.texture.resource_path.ends_with("mirage_inn_owner_room_layer_plate.png"),
		"BeginningFP should use the owner room plate (lantern and scroll painted out)"
	)
	scene.free()

func test_beginning_scene_stacks_the_three_owner_room_layers() -> void:
	var packed: PackedScene = load(BEGINNING_SCENE_PATH)
	var scene: Node = packed.instantiate()
	for node_name: String in OWNER_ROOM_LAYERS:
		var node: Sprite2D = scene.get_node_or_null(node_name)
		assert_not_null(node, "%s layer should exist" % node_name)
		if node == null:
			continue
		assert_not_null(node.texture, "%s should have a texture" % node_name)
		if node.texture != null:
			assert_true(
				node.texture.resource_path.ends_with(OWNER_ROOM_LAYERS[node_name]),
				"%s should use %s" % [node_name, OWNER_ROOM_LAYERS[node_name]]
			)
		# centered=false draws the texture from `offset`; position + offset must land
		# the crop on the pixel it came from in the flat background.
		assert_false(node.centered, "%s should be top-left anchored" % node_name)
		assert_eq(node.position + node.offset, OWNER_ROOM_LAYER_ORIGINS[node_name],
			"%s should land on its original crop origin" % node_name)
		assert_lt(node.z_index, 0, "%s should draw behind the room props" % node_name)
	assert_lt(
		float(scene.get_node("OwnerRoomBackground").z_index),
		float(scene.get_node("OwnerRoomLantern").z_index),
		"the plate must draw behind the lantern"
	)
	assert_lt(
		float(scene.get_node("OwnerRoomBackground").z_index),
		float(scene.get_node("OwnerRoomScroll").z_index),
		"the plate must draw behind the scroll"
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
