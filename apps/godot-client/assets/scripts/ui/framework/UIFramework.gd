## UIFramework.gd
## UI框架系统 — 4层CanvasLayer管理 + 页面栈
## 设计目标：统一UI层级管理，页面过渡动画，响应式布局
## Godot 4.6, GDScript static typing

class_name UIFramework
extends Node

## ============================================================
## CanvasLayer层级定义
## ============================================================

enum LayerIndex {
    SCENE = 0,      # z=0: 场景内容、交互对象、NPC
    HUD = 1,        # z=10: 游戏HUD、任务追踪、计时器
    DIALOGUE = 2,   # z=20: 对话气泡、语音输入、星级评价
    OVERLAY = 3     # z=30: Spark覆盖、解锁仪式、奖励动画
}

## Layer z-index配置
const LAYER_Z_INDEX: Dictionary = {
    LayerIndex.SCENE: 0,
    LayerIndex.HUD: 10,
    LayerIndex.DIALOGUE: 20,
    LayerIndex.OVERLAY: 30
}

## ============================================================
## 响应式布局配置
## ============================================================

## 基础分辨率
const BASE_RESOLUTION: Vector2 = Vector2(1920, 1080)

## 安全区域边距 (距离边缘5% viewport)
const SAFE_MARGIN_RATIO: float = 0.05

## ============================================================
## 页面栈管理
## ============================================================

## 页面栈 (Push/Pop)
var page_stack: Array[Control] = []

## 最大页面栈深度
const MAX_PAGE_STACK_DEPTH: int = 10

## 当前遮罩节点
var current_overlay: Control = null

## ============================================================
## CanvasLayer节点引用
## ============================================================

var scene_layer: CanvasLayer
var hud_layer: CanvasLayer
var dialogue_layer: CanvasLayer
var overlay_layer: CanvasLayer

## ============================================================
## 信号定义
## ============================================================

signal page_pushed(page: Control)
signal page_popped(page: Control)
signal overlay_shown(overlay: Control)
signal overlay_hidden(overlay: Control)
signal layer_created(layer_index: LayerIndex, canvas_layer: CanvasLayer)

## ============================================================
## 初始化 — 创建4层CanvasLayer
## ============================================================

func _ready() -> void:
    # 创建4个CanvasLayer节点
    scene_layer = _create_canvas_layer(LayerIndex.SCENE, "SceneCanvasLayer")
    hud_layer = _create_canvas_layer(LayerIndex.HUD, "HUDCanvasLayer")
    dialogue_layer = _create_canvas_layer(LayerIndex.DIALOGUE, "DialogueCanvasLayer")
    overlay_layer = _create_canvas_layer(LayerIndex.OVERLAY, "OverlayCanvasLayer")

    # 设置基础分辨率
    _setup_base_resolution()

## ============================================================
## 创建CanvasLayer节点
## ============================================================

func _create_canvas_layer(layer_index: LayerIndex, layer_name: String) -> CanvasLayer:
    var canvas_layer = CanvasLayer.new()
    canvas_layer.name = layer_name
    canvas_layer.layer = LAYER_Z_INDEX[layer_index]

    # 添加到场景树
    add_child(canvas_layer)
    layer_created.emit(layer_index, canvas_layer)

    return canvas_layer

## ============================================================
## 设置基础分辨率
## ============================================================

func _setup_base_resolution() -> void:
    # 设置窗口大小（编辑器模式下）
    if Engine.is_editor_hint():
        return

    # 实际游戏运行时，通过project.godot配置
    # 这里仅作为备用设置
    var viewport = get_viewport()
    viewport.content_scale_size = BASE_RESOLUTION
    viewport.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    viewport.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

## ============================================================
## 页面栈：Push页面 (从右侧滑入)
## ============================================================

func push_page(page: Control, layer: LayerIndex = LayerIndex.HUD) -> void:
    # 检查页面栈深度限制
    if page_stack.size() >= MAX_PAGE_STACK_DEPTH:
        push_warning("[UIFramework] 页面栈达到最大深度 %d，拒绝Push" % MAX_PAGE_STACK_DEPTH)
        return

    # 获取目标CanvasLayer
    var target_layer = _get_layer_by_index(layer)

    # 添加到CanvasLayer
    target_layer.add_child(page)

    # 添加到页面栈
    page_stack.append(page)

    # 播放Push动画 (从右侧滑入，0.3s)
    _play_push_animation(page)

    # 发出信号
    page_pushed.emit(page)

## ============================================================
## 页面栈：Pop页面 (向右侧滑出)
## ============================================================

func pop_page() -> Control:
    if page_stack.is_empty():
        push_warning("[UIFramework] 页面栈为空，无法Pop")
        return null

    # 获取栈顶页面
    var top_page = page_stack.pop_back()

    # 播放Pop动画 (向右侧滑出，0.25s)
    _play_pop_animation(top_page)

    # 动画完成后移除节点
    await get_tree().create_timer(0.25).timeout
    top_page.get_parent().remove_child(top_page)

    # 发出信号
    page_popped.emit(top_page)

    return top_page

## ============================================================
## 页面Push动画 (从右侧滑入)
## ============================================================

func _play_push_animation(page: Control) -> void:
    var viewport_width = get_viewport().get_visible_rect().size.x

    # 初始位置：屏幕右侧外
    page.position.x = viewport_width
    page.visible = true

    # Tween动画：滑入
    var tween = create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(page, "position:x", 0.0, 0.3)

## ============================================================
## 页面Pop动画 (向右侧滑出)
## ============================================================

func _play_pop_animation(page: Control) -> void:
    var viewport_width = get_viewport().get_visible_rect().size.x

    # Tween动画：滑出
    var tween = create_tween()
    tween.set_trans(Tween.TRANS_CUBIC)
    tween.set_ease(Tween.EASE_IN)
    tween.tween_property(page, "position:x", viewport_width, 0.25)

## ============================================================
## Overlay遮罩显示
## ============================================================

func show_overlay(overlay: Control) -> void:
    if current_overlay != null:
        # 隐藏现有遮罩
        hide_overlay()

    # 添加到OverlayLayer
    overlay_layer.add_child(overlay)
    current_overlay = overlay

    # 播放弹出动画 (ScalePop)
    _play_overlay_show_animation(overlay)

    # 发出信号
    overlay_shown.emit(overlay)

## ============================================================
## Overlay遮罩隐藏
## ============================================================

func hide_overlay() -> void:
    if current_overlay == null:
        return

    # 播放淡出动画
    _play_overlay_hide_animation(current_overlay)

    # 动画完成后移除
    await get_tree().create_timer(0.25).timeout
    overlay_layer.remove_child(current_overlay)
    current_overlay.queue_free()
    current_overlay = null

    # 发出信号
    overlay_hidden.emit(current_overlay)

## ============================================================
## Overlay显示动画
## ============================================================

func _play_overlay_show_animation(overlay: Control) -> void:
    overlay.scale = Vector2(0.5, 0.5)
    overlay.modulate.a = 0.0
    overlay.visible = true

    var tween = create_tween()
    tween.set_trans(Tween.TRANS_BACK)
    tween.set_ease(Tween.EASE_OUT)

    # 淡入
    tween.parallel().tween_property(overlay, "modulate:a", 1.0, 0.2)

    # 弹性缩放 (先放大到1.15，再回到1.0)
    tween.tween_property(overlay, "scale", Vector2(1.15, 1.15), 0.24)
    tween.tween_property(overlay, "scale", Vector2(1.0, 1.0), 0.16)

## ============================================================
## Overlay隐藏动画
## ============================================================

func _play_overlay_hide_animation(overlay: Control) -> void:
    var tween = create_tween()
    tween.set_trans(Tween.TRANS_QUAD)
    tween.set_ease(Tween.EASE_IN)

    tween.parallel().tween_property(overlay, "modulate:a", 0.0, 0.25)
    tween.tween_property(overlay, "scale", Vector2(0.8, 0.8), 0.25)

## ============================================================
## 获取Layer节点
## ============================================================

func _get_layer_by_index(layer_index: LayerIndex) -> CanvasLayer:
    match layer_index:
        LayerIndex.SCENE:
            return scene_layer
        LayerIndex.HUD:
            return hud_layer
        LayerIndex.DIALOGUE:
            return dialogue_layer
        LayerIndex.OVERLAY:
            return overlay_layer
    return scene_layer  # 默认返回场景层

## ============================================================
## 安全区域计算
## ============================================================

## 计算安全区域矩形 (避开边缘5%)
func get_safe_area_rect() -> Rect2:
    var viewport_size = get_viewport().get_visible_rect().size
    var margin_x = viewport_size.x * SAFE_MARGIN_RATIO
    var margin_y = viewport_size.y * SAFE_MARGIN_RATIO

    return Rect2(
        Vector2(margin_x, margin_y),
        Vector2(viewport_size.x - 2 * margin_x, viewport_size.y - 2 * margin_y)
    )

## ============================================================
## 公共接口
## ============================================================

## 获取指定Layer
func get_layer(layer_index: LayerIndex) -> CanvasLayer:
    return _get_layer_by_index(layer_index)

## 获取页面栈深度
func get_page_stack_depth() -> int:
    return page_stack.size()

## 获取栈顶页面
func get_top_page() -> Control:
    if page_stack.is_empty():
        return null
    return page_stack.back()

## 清空页面栈
func clear_page_stack() -> void:
    while page_stack.size() > 0:
        pop_page()

## 强制清空（跳过动画）
func force_clear_page_stack() -> void:
    for page in page_stack:
        page.get_parent().remove_child(page)
        page.queue_free()
    page_stack.clear()