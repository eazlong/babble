## SceneManagementSystem.gd
## 场景管理系统 — 14步场景切换流程 + 状态机
## 设计目标：流畅场景切换，异步资源加载，内存安全卸载
## Godot 4.6, GDScript static typing

class_name SceneManagementSystem
extends Node

## ============================================================
## 场景状态枚举
## ============================================================

enum SceneState {
    UNINITIALIZED,      # 未初始化
    IDLE,               # 空闲（无场景）
    TRANSITIONING_IN,   # 进入过渡中
    ACTIVE,             # 场景激活
    TRANSITIONING_OUT,  # 退出过渡中
    ERROR               # 错误状态
}

## ============================================================
## 场景配置
## ============================================================

## 当前场景状态
var current_state: SceneState = SceneState.UNINITIALIZED

## 当前场景ID
var current_scene_id: String = ""

## 场景配置字典 (加载自JSON)
var scene_configs: Dictionary = {}

## 场景资源缓存
var loaded_scenes: Dictionary = {}  # String -> PackedScene

## ============================================================
## 性能预算 (每步)
## ============================================================

const STEP_BUDGET_MS: int = 100      # 每步预算100ms
const STEP_TIMEOUT_MS: int = 150     # 超时阈值150ms

## ============================================================
## 信号定义
## ============================================================

signal scene_entering(scene_id: String)
signal scene_entered(scene_id: String, scene_name: String)
signal scene_exiting(scene_id: String)
signal scene_exited(scene_id: String)
signal transition_started(scene_id: String)
signal transition_completed(scene_id: String)
signal transition_failed(scene_id: String, error: String)
signal state_changed(old_state: SceneState, new_state: SceneState)

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
    # 加载场景配置
    _load_scene_configs()

    # 初始化状态
    current_state = SceneState.IDLE

## ============================================================
## 加载场景配置 (从JSON)
## ============================================================

func _load_scene_configs() -> void:
    var config_path = "res://assets/resources/scene_configs/"
    var config_files = [
        "spirit_forest.json",
        "spell_library.json",
        "rainbow_garden.json"
    ]

    for config_file in config_files:
        var full_path = config_path + config_file
        if ResourceLoader.exists(full_path):
            var json_text = FileAccess.open(full_path, FileAccess.READ).get_as_text()
            var json = JSON.new()
            if json.parse(json_text) == OK:
                var config = json.data
                var scene_id = config.get("scene_id", "")
                if scene_id != "":
                    scene_configs[scene_id] = config

## ============================================================
## 主接口：进入场景 (14步流程)
## ============================================================

func enter_scene(scene_id: String) -> bool:
    ## Step 1: 验证状态 (仅IDLE允许)
    if current_state != SceneState.IDLE:
        transition_failed.emit(scene_id, "Invalid state: %s" % current_state)
        return false

    ## Step 2: 验证scene_id存在
    if not scene_configs.has(scene_id):
        transition_failed.emit(scene_id, "Scene config not found")
        return false

    ## Step 3: 验证场景解锁
    var config: Dictionary = scene_configs[scene_id]
    if not _check_scene_unlocked(config):
        transition_failed.emit(scene_id, "Scene locked")
        return false

    ## Step 4: 退出当前场景 (如果有)
    if current_scene_id != "":
        _exit_current_scene()

    ## Step 5: 状态 → TRANSITIONING_IN
    _change_state(SceneState.TRANSITIONING_IN)
    transition_started.emit(scene_id)

    ## Step 6: 阻塞输入
    _block_input()

    ## Step 7: 加载资源 (异步)
    var scene_resource = _load_scene_resource(scene_id)
    if scene_resource == null:
        transition_failed.emit(scene_id, "Scene resource load failed")
        _change_state(SceneState.ERROR)
        _unblock_input()
        return false

    ## Step 8: 注册主要NPC
    _register_primary_npc(config)

    ## Step 9: 触发entry_events
    _trigger_entry_events(config)

    ## Step 10: 发出scene_entering信号
    scene_entering.emit(scene_id)

    ## Step 11: 过渡动画
    _play_transition_animation()

    ## Step 12: 解除输入阻塞
    _unblock_input()

    ## Step 13: 状态 → ACTIVE
    _change_state(SceneState.ACTIVE)
    current_scene_id = scene_id

    ## Step 14: 发出scene_entered + scene_name_display信号
    var scene_name = config.get("scene_name", "Unknown Scene")
    scene_entered.emit(scene_id, scene_name)

    transition_completed.emit(scene_id)
    return true

## ============================================================
## 退出场景流程
## ============================================================

func _exit_current_scene() -> void:
    if current_scene_id == "":
        return

    ## Step A: 状态 → TRANSITIONING_OUT
    _change_state(SceneState.TRANSITIONING_OUT)
    scene_exiting.emit(current_scene_id)

    ## Step B: 阻塞输入
    _block_input()

    ## Step C: 播放退出过渡动画
    _play_exit_transition()

    ## Step D: 停止音频
    _stop_audio()

    ## Step E: 保存状态
    _save_scene_state()

    ## Step F: 清理节点
    _clean_scene_nodes()

    ## Step G: 释放资源
    _release_scene_resources()

    ## Step H: 解除输入阻塞
    _unblock_input()

    ## Step I: 状态 → IDLE
    _change_state(SceneState.IDLE)
    scene_exited.emit(current_scene_id)
    current_scene_id = ""

## ============================================================
## 14步流程的具体实现
## ============================================================

## Step 3: 验证场景解锁
func _check_scene_unlocked(config: Dictionary) -> bool:
    var unlock_condition = config.get("unlock_condition", {})
    # 检查解锁条件（例如：完成前置任务）
    # 实际实现需要连接GameManager/QuestWebSocket
    return true  # 默认解锁

## Step 7: 加载场景资源 (异步)
func _load_scene_resource(scene_id: String) -> PackedScene:
    var config: Dictionary = scene_configs[scene_id]
    var scene_path = config.get("scene_path", "")

    if scene_path == "":
        return null

    # 检查缓存
    if loaded_scenes.has(scene_id):
        return loaded_scenes[scene_id]

    # 异步加载
    var status = ResourceLoader.load_threaded_request(scene_path)
    if status != OK:
        return null

    # 等待加载完成
    while ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
        await get_tree().process_frame

    var scene_resource = ResourceLoader.load_threaded_get(scene_path)
    if scene_resource == null:
        return null

    # 缓存场景
    loaded_scenes[scene_id] = scene_resource
    return scene_resource

## Step 8: 注册主要NPC
func _register_primary_npc(config: Dictionary) -> void:
    var primary_npc = config.get("primary_npc", {})
    if primary_npc.is_empty():
        return

    # 实际实现需要连接NPCController
    # spawn_npc(primary_npc)

## Step 9: 触发entry_events
func _trigger_entry_events(config: Dictionary) -> void:
    var entry_events = config.get("entry_events", [])
    for event in entry_events:
        # 触发事件（例如：播放背景音乐、显示教程）
        _trigger_event(event)

## Step 11: 过渡动画
func _play_transition_animation() -> void:
    # 使用ShaderManager的transition_wipe Shader
    var shader_manager = get_node_or_null("/root/ShaderManager")
    if shader_manager:
        # 创建过渡层（CanvasLayer Layer 4）
        var transition_layer = CanvasLayer.new()
        transition_layer.layer = 40  # 最高层
        transition_layer.name = "TransitionLayer"
        get_tree().root.add_child(transition_layer)

        # 创建过渡精灵（全屏）
        var transition_sprite = ColorRect.new()
        transition_sprite.color = Color.BLACK
        transition_sprite.size = get_viewport().get_visible_rect().size
        transition_sprite.position = Vector2.ZERO
        transition_layer.add_child(transition_sprite)

        # 应用transition_wipe shader
        var shader_material = shader_manager.apply_shader(transition_sprite, "transition_wipe")

        # 使用ShaderAnimator播放过渡动画
        var shader_anim = ShaderAnimator.new()
        add_child(shader_anim)
        shader_anim.create(transition_sprite)
        shader_anim.animate_float("progress", 0.0, 1.0, 0.3)

        # 等待动画完成
        await get_tree().create_timer(0.3).timeout

        # 清理过渡层
        transition_layer.queue_free()
        shader_anim.queue_free()
    else:
        # 备用方案：简单淡入
        await get_tree().create_timer(0.3).timeout

## Step B-C: 退出过渡动画
func _play_exit_transition() -> void:
    # 反向过渡动画（progress: 1.0 → 0.0）
    var shader_manager = get_node_or_null("/root/ShaderManager")
    if shader_manager:
        # 创建过渡层
        var transition_layer = CanvasLayer.new()
        transition_layer.layer = 40
        transition_layer.name = "ExitTransitionLayer"
        get_tree().root.add_child(transition_layer)

        # 创建过渡精灵
        var transition_sprite = ColorRect.new()
        transition_sprite.color = Color.BLACK
        transition_sprite.size = get_viewport().get_visible_rect().size
        transition_sprite.position = Vector2.ZERO
        transition_layer.add_child(transition_sprite)

        # 应用transition_wipe shader
        var shader_material = shader_manager.apply_shader(transition_sprite, "transition_wipe")
        shader_material.set_shader_parameter("progress", 1.0)

        # 反向动画
        var shader_anim = ShaderAnimator.new()
        add_child(shader_anim)
        shader_anim.create(transition_sprite)
        shader_anim.animate_float("progress", 1.0, 0.0, 0.25)

        # 等待动画完成
        await get_tree().create_timer(0.25).timeout

        # 清理
        transition_layer.queue_free()
        shader_anim.queue_free()
    else:
        # 备用：简单淡出
        await get_tree().create_timer(0.25).timeout

## Step D: 停止音频
func _stop_audio() -> void:
    if has_node("/root/AudioManager"):
        var audio_manager = get_node("/root/AudioManager")
        # audio_manager.stop_all()

## Step E: 保存状态
func _save_scene_state() -> void:
    if has_node("/root/SaveSystem"):
        var save_system = get_node("/root/SaveSystem")
        # save_system.save_scene_state(current_scene_id)

## Step F: 清理节点
func _clean_scene_nodes() -> void:
    # 获取当前场景根节点并清理
    var current_scene_node = get_tree().current_scene
    if current_scene_node:
        for child in current_scene_node.get_children():
            if child is CanvasLayer:
                # 保留CanvasLayer，清理内容
                pass
            else:
                child.queue_free()

## Step G: 释放资源
func _release_scene_resources() -> void:
    # 释放纹理、音频等资源
    # 实际实现需要更细粒度管理
    pass

## ============================================================
## 输入阻塞/解除
## ============================================================

## 输入阻塞标志
var _input_blocked: bool = false

func _block_input() -> void:
    # 设置全局输入阻塞标志
    _input_blocked = true

    # 通知UIFramework
    var ui_framework = get_node_or_null("/root/UIFramework")
    if ui_framework:
        ui_framework.set_input_blocked(true)

func _unblock_input() -> void:
    # 解除输入阻塞
    _input_blocked = false

    # 通知UIFramework
    var ui_framework = get_node_or_null("/root/UIFramework")
    if ui_framework:
        ui_framework.set_input_blocked(false)

## 检查输入是否被阻塞（供外部调用）
func is_input_blocked() -> bool:
    return _input_blocked

## ============================================================
## 状态变更
## ============================================================

func _change_state(new_state: SceneState) -> void:
    var old_state = current_state
    current_state = new_state
    state_changed.emit(old_state, new_state)

## ============================================================
## 事件触发
## ============================================================

func _trigger_event(event: Dictionary) -> void:
    var event_type = event.get("type", "")
    match event_type:
        "play_bgm":
            _event_play_bgm(event)
        "show_tutorial":
            _event_show_tutorial(event)
        "spawn_particle":
            _event_spawn_particle(event)

func _event_play_bgm(event: Dictionary) -> void:
    var bgm_path = event.get("bgm_path", "")
    if bgm_path != "" and has_node("/root/AudioManager"):
        # AudioManager.play_bgm(bgm_path)
        pass

func _event_show_tutorial(event: Dictionary) -> void:
    var tutorial_id = event.get("tutorial_id", "")
    # 显示教程（连接DialogueManager）
    pass

func _event_spawn_particle(event: Dictionary) -> void:
    var particle_type = event.get("particle_type", "")
    var position = event.get("position", Vector2.ZERO)
    if has_node("/root/VFXManager"):
        # VFXManager.play_particle(particle_type, position)
        pass

## ============================================================
## 公共接口
## ============================================================

## 获取当前场景ID
func get_current_scene_id() -> String:
    return current_scene_id

## 获取当前状态
func get_current_state() -> SceneState:
    return current_state

## 获取场景配置
func get_scene_config(scene_id: String) -> Dictionary:
    return scene_configs.get(scene_id, {})

## 列出所有可用场景
func list_available_scenes() -> Array[String]:
    var available: Array[String] = []
    for scene_id in scene_configs.keys():
        if _check_scene_unlocked(scene_configs[scene_id]):
            available.append(scene_id)
    return available

## 强制切换场景（跳过状态检查）
func force_enter_scene(scene_id: String) -> bool:
    # 紧急情况使用，跳过状态验证
    current_state = SceneState.IDLE
    return enter_scene(scene_id)