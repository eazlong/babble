## UI框架系统 — 核心单例
## 管理4层CanvasLayer、页面栈、主题加载、响应式布局
## ADR-0003: UI CanvasLayer 4层分层策略
## GDD: design/gdd/ui-framework.md

extends Node

# ============================================================
# 信号
# ============================================================

## Layer 3 Overlay 激活（设置/词灵展示/引导打开）
signal overlay_activated()

## Layer 3 Overlay 关闭
signal overlay_deactivated()

## 页面栈变化
signal page_stack_changed(current_depth: int)

## 页面Push完成
signal page_pushed(page_name: String)

## 页面Pop完成
signal page_popped(page_name: String)

# ============================================================
# 常量
# ============================================================

## CanvasLayer 层索引（对应 ADR-0003 layer 值）
enum LayerIndex {
	SCENE = 0,     # Layer 0 — 游戏世界（场景管理系统）
	HUD = 1,       # Layer 1 — HUD（UI框架系统）
	DIALOGUE = 2,  # Layer 2 — 对话（对话UI系统）
	OVERLAY = 3,   # Layer 3 — 覆盖层（UI框架系统）
}

## CanvasLayer layer 属性值
const LAYER_SCENE := 0
const LAYER_HUD := 10
const LAYER_DIALOGUE := 20
const LAYER_OVERLAY := 30

## 页面栈最大深度
const MAX_PAGE_STACK := 3

## 页面Push动画时长（秒）
const PAGE_PUSH_DURATION := 0.3

## 页面Pop动画时长（秒）
const PAGE_POP_DURATION := 0.25

## Overlay激活时下层不透明度
const OVERLAY_DIM_OPACITY := 0.3

## 防抖间隔（秒）— 防止快速连续Push/Pop
const PAGE_ACTION_DEBOUNCE := 0.5

# ============================================================
# CanvasLayer 节点
# ============================================================

var _scene_canvas: CanvasLayer
var _hud_canvas: CanvasLayer
var _dialogue_canvas: CanvasLayer
var _overlay_canvas: CanvasLayer

## Content Control wrappers inside CanvasLayers (for modulate/opacity)
var _hud_content: Control
var _dialogue_content: Control

# ============================================================
# 页面栈
# ============================================================

var _page_stack: Array[Control] = []

## 当前是否有页面正在动画（防抖）
var _page_animating: bool = false

# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	# TODO: CJK font loading disabled - font files not importing correctly
	# _setup_cjk_font()
	_create_canvas_layers()
	print("[UIFramework] Created 4 CanvasLayers (Scene=0, HUD=10, Dialogue=20, Overlay=30)")


func _setup_cjk_font() -> void:
	# Disabled: STHeiti font files (both .ttc and .ttf) not importing in Godot 4.6
	# var font := load("res://assets/resources/fonts/STHeiti-Regular.ttf") as Font
	# if font:
	# 	get_tree().root.add_theme_font_override("font", font)
	pass


## 创建4个CanvasLayer节点（ADR-0003）
func _create_canvas_layers() -> void:
	# Layer 0 — 游戏世界
	_scene_canvas = _make_canvas_layer("SceneCanvasLayer", LAYER_SCENE, "Game World Layer")
	get_tree().root.add_child.call_deferred(_scene_canvas)

	# Layer 1 — HUD (with content wrapper for modulate)
	_hud_canvas = _make_canvas_layer("HUDCanvasLayer", LAYER_HUD, "HUD Layer")
	_hud_content = Control.new()
	_hud_content.name = "HUDContent"
	_hud_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_canvas.add_child(_hud_content)
	get_tree().root.add_child.call_deferred(_hud_canvas)

	# Layer 2 — 对话 (with content wrapper for modulate)
	_dialogue_canvas = _make_canvas_layer("DialogueCanvasLayer", LAYER_DIALOGUE, "Dialogue Layer")
	_dialogue_content = Control.new()
	_dialogue_content.name = "DialogueContent"
	_dialogue_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogue_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_canvas.add_child(_dialogue_content)
	get_tree().root.add_child.call_deferred(_dialogue_canvas)

	# Layer 3 — 覆盖层（初始隐藏）
	_overlay_canvas = _make_canvas_layer("OverlayCanvasLayer", LAYER_OVERLAY, "Overlay Layer")
	_overlay_canvas.visible = false
	get_tree().root.add_child.call_deferred(_overlay_canvas)


## 创建单个CanvasLayer节点
func _make_canvas_layer(name: String, layer_value: int, _accessibility_label: String) -> CanvasLayer:
	var canvas := CanvasLayer.new()
	canvas.name = name
	canvas.layer = layer_value
	return canvas


# ============================================================
# 层访问接口（下游系统使用）
# ============================================================

## 获取指定层的CanvasLayer节点
## 参数: index — LayerIndex枚举值
## 返回: 对应CanvasLayer，无效index返回null
func get_layer_root(index: int) -> CanvasLayer:
	match index:
		LayerIndex.SCENE:
			return _scene_canvas
		LayerIndex.HUD:
			return _hud_canvas
		LayerIndex.DIALOGUE:
			return _dialogue_canvas
		LayerIndex.OVERLAY:
			return _overlay_canvas
	push_warning("UIFramework: 无效层索引 %d" % index)
	return null


# ============================================================
# 不透明度控制（Layer 3 Overlay 激活时调用）
# ============================================================

## 设置Layer 1-2不透明度
## Layer 3激活时: set_layer_opacity(LayerIndex.HUD, 0.3), set_layer_opacity(LayerIndex.DIALOGUE, 0.3)
## Layer 3关闭时: set_layer_opacity(LayerIndex.HUD, 1.0), set_layer_opacity(LayerIndex.DIALOGUE, 1.0)
func set_layer_opacity(index: int, opacity: float, duration: float = 0.2) -> void:
	opacity = clampf(opacity, 0.0, 1.0)
	var target: Control
	match index:
		LayerIndex.HUD:
			target = _hud_content
		LayerIndex.DIALOGUE:
			target = _dialogue_content
		LayerIndex.SCENE, LayerIndex.OVERLAY:
			push_warning("UIFramework: 层 %d 不支持opacity控制" % index)
			return
		_:
			push_warning("UIFramework: 无效层索引 %d" % index)
			return

	if not target:
		return

	if duration <= 0.0:
		target.modulate.a = opacity
		return

	var tree := get_tree()
	if not tree:
		target.modulate.a = opacity
		return

	var tween := tree.create_tween()
	tween.tween_property(target, "modulate:a", opacity, duration)


## 激活Overlay（Layer 1-2 dim 至 30%）
func activate_overlay() -> void:
	if _overlay_canvas:
		_overlay_canvas.visible = true
	set_layer_opacity(LayerIndex.HUD, OVERLAY_DIM_OPACITY)
	set_layer_opacity(LayerIndex.DIALOGUE, OVERLAY_DIM_OPACITY)
	overlay_activated.emit()


## 关闭Overlay（Layer 1-2恢复100%不透明度）
func deactivate_overlay() -> void:
	set_layer_opacity(LayerIndex.HUD, 1.0)
	set_layer_opacity(LayerIndex.DIALOGUE, 1.0)
	if _overlay_canvas:
		_overlay_canvas.visible = false
	overlay_deactivated.emit()


# ============================================================
# 页面栈管理
# ============================================================

## Push页面到栈（新页面从右侧滑入）
## 参数: scene — PackedScene，必须根节点为Control
## 返回: true成功，false失败（栈满/scene无效）
func push_page(scene: PackedScene) -> bool:
	if _page_animating:
		push_warning("UIFramework: 页面动画中，忽略Push请求")
		return false

	if _page_stack.size() >= MAX_PAGE_STACK:
		push_warning("UIFramework: 页面栈已满（%d层），拒绝Push" % MAX_PAGE_STACK)
		return false

	if not scene:
		push_warning("UIFramework: push_page收到空scene")
		return false

	var page: Control = scene.instantiate()
	if not page is Control:
		push_warning("UIFramework: 页面根节点不是Control，无法添加到页面栈")
		page.queue_free()
		return false

	_page_animating = true
	_hud_content.add_child(page)
	_page_stack.append(page)
	page_stack_changed.emit(_page_stack.size())

	# 页面初始位置：屏幕右侧外
	var viewport_size := _get_viewport_size()
	page.position.x = viewport_size.x

	# 滑入动画
	var tree := get_tree()
	if tree:
		var tween := tree.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(page, "position:x", 0.0, PAGE_PUSH_DURATION)
		tween.tween_callback(_on_push_complete.bind(page))
	else:
		page.position.x = 0.0
		_on_push_complete(page)

	return true


## Pop栈顶页面（从右侧滑出）
func pop_page() -> bool:
	if _page_animating:
		push_warning("UIFramework: 页面动画中，忽略Pop请求")
		return false

	if _page_stack.is_empty():
		# 空栈安全处理 — 不crash不报错（GDD EC1）
		return false

	_page_animating = true
	var page: Control = _page_stack.back()
	var page_name: String = page.name

	# 滑出动画
	var viewport_size := _get_viewport_size()
	var tree := get_tree()
	if tree:
		var tween := tree.create_tween()
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(page, "position:x", viewport_size.x, PAGE_POP_DURATION)
		tween.tween_callback(_on_pop_complete.bind(page, page_name))
	else:
		_on_pop_complete(page, page_name)

	return true


func _on_push_complete(page: Control) -> void:
	_page_animating = false
	page_pushed.emit(page.name)


func _on_pop_complete(page: Control, page_name: String) -> void:
	_page_stack.pop_back()
	page.queue_free()
	_page_animating = false
	page_stack_changed.emit(_page_stack.size())
	page_popped.emit(page_name)


# ============================================================
# 状态查询
# ============================================================

## 当前页面栈深度
func get_stack_depth() -> int:
	return _page_stack.size()


## 栈顶页面（不弹出）
func get_top_page() -> Control:
	if _page_stack.is_empty():
		return null
	return _page_stack.back()


## 获取viewport尺寸
func _get_viewport_size() -> Vector2:
	var viewport := get_viewport()
	if viewport:
		return viewport.get_visible_rect().size
	push_warning("UIFramework: 无法获取viewport，使用默认1920x1080")
	return Vector2(1920, 1080)
