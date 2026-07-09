# UIFramework单元测试（最简版 - 使用autoload）
extends GutTest

# UIFramework是autoload，直接使用实例

func before_all():
	# UIFramework已在autoload中初始化
	await wait_seconds(0.1)

# ── CanvasLayer创建测试 ──

func test_ui_framework_exists():
	assert_not_null(UIFramework, "UIFramework autoload应存在")

func test_canvas_layers_created():
	assert_not_null(UIFramework._scene_canvas, "SceneCanvasLayer应创建")
	assert_not_null(UIFramework._hud_canvas, "HUDCanvasLayer应创建")
	assert_not_null(UIFramework._dialogue_canvas, "DialogueCanvasLayer应创建")
	assert_not_null(UIFramework._overlay_canvas, "OverlayCanvasLayer应创建")

func test_layer_constants():
	assert_eq(UIFramework.LAYER_SCENE, 0, "Scene layer常量为0")
	assert_eq(UIFramework.LAYER_HUD, 10, "HUD layer常量为10")
	assert_eq(UIFramework.LAYER_DIALOGUE, 20, "Dialogue layer常量为20")
	assert_eq(UIFramework.LAYER_OVERLAY, 30, "Overlay layer常量为30")

func test_overlay_initially_hidden():
	assert_false(UIFramework._overlay_canvas.visible, "Overlay初始应隐藏")

func test_get_layer_root():
	var scene_layer = UIFramework.get_layer_root(UIFramework.LayerIndex.SCENE)
	assert_eq(scene_layer, UIFramework._scene_canvas, "应返回正确layer")

# ── Overlay激活测试 ──

func test_activate_overlay_shows_canvas():
	UIFramework.activate_overlay()
	assert_true(UIFramework._overlay_canvas.visible, "Overlay应显示")

func test_deactivate_overlay_hides_canvas():
	UIFramework.activate_overlay()
	await wait_seconds(0.1)
	UIFramework.deactivate_overlay()
	assert_false(UIFramework._overlay_canvas.visible, "Overlay应隐藏")

# ── 状态查询测试 ──

func test_get_stack_depth_initial():
	assert_eq(UIFramework.get_stack_depth(), 0, "初始栈深度为0")