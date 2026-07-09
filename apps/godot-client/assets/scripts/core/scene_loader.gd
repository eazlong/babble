class_name SceneLoader
extends RefCounted

## Story: SM-09 — 场景加载系统
## 实现异步场景加载，包含配置加载、资源加载、状态初始化
## 支持加载队列、进度回调、超时检测、错误降级

# ==================== Signals ====================

## 加载进度变化信号
## progress: 0-100 的整数进度值
signal load_progress_changed(progress: int)

## 场景加载完成信号
## scene_id: 完成加载的场景ID
## scene_data: 包含所有加载资源的字典
signal load_completed(scene_id: String, scene_data: Dictionary)

## 场景加载失败信号
## scene_id: 失败的场景ID
## error: 错误代码 (见 Error 枚举)
signal load_failed(scene_id: String, error: int)

## 单个阶段完成信号（用于测试和调试）
signal stage_completed(stage: String)

# ==================== Constants ====================

## 加载超时时间（毫秒）
const TIMEOUT_MS: int = 5000

## 进度更新间隔（毫秒）
const UPDATE_INTERVAL_MS: int = 50

## 队列最大长度
const MAX_QUEUE_SIZE: int = 3

## 加载阶段权重（用于进度计算）
const CONFIG_WEIGHT: float = 0.1
const BACKGROUND_WEIGHT: float = 0.3
const AUDIO_WEIGHT: float = 0.3
const INIT_WEIGHT: float = 0.3

## 错误代码枚举
enum Error {
    NONE = 0,
    INVALID_SCENE = 1,      ## 无效的场景ID
    CONFIG_NOT_FOUND = 2,   ## 配置文件缺失
    TIMEOUT = 3,            ## 加载超时
    RESOURCE_LOAD_FAILED = 4, ## 资源加载失败
    QUEUE_FULL = 5,         ## 队列已满
    UNKNOWN = 99            ## 未知错误
}

## 加载阶段枚举
enum LoadingStage {
    IDLE,                   ## 空闲状态
    LOADING_CONFIG,         ## 正在加载配置
    LOADING_BACKGROUND,     ## 正在加载背景
    LOADING_AUDIO,          ## 正在加载音频
    INITIALIZING,           ## 正在初始化
    LOADED,                 ## 加载完成
    ERROR                   ## 加载错误
}

# ==================== Properties ====================

## 当前加载阶段
var current_stage: LoadingStage = LoadingStage.IDLE

## 当前加载的场景ID
var current_scene_id: String = ""

## 当前场景配置
var current_config: SceneConfig = null

## 加载开始时间（毫秒）
var _load_start_time: int = 0

## 上次进度更新时间
var _last_progress_time: int = 0

## 加载队列（存储待加载的场景ID）
var _load_queue: Array[String] = []

## 是否正在加载中
var _is_loading: bool = false

## 当前加载进度（0-100）
var _current_progress: int = 0

## 加载的资源缓存
var _loaded_resources: Dictionary = {}

## 降级标志
var _using_default_config: bool = false
var _using_fallback_background: bool = false
var _using_silent_audio: bool = false

## 当前资源加载路径（用于 ResourceLoader 跟踪）
var _current_resource_path: String = ""

## 资源加载进度数组（Godot ResourceLoader API 需要）
var _resource_progress: Array[float] = [0.0]

# ==================== Public API ====================

## 请求加载场景
## scene_id: 要加载的场景ID
## 返回: true 如果请求被接受（加入队列或开始加载），false 如果队列已满
func request_load(scene_id: String) -> bool:
    if scene_id.is_empty():
        push_error("SceneLoader: scene_id cannot be empty")
        load_failed.emit(scene_id, Error.INVALID_SCENE)
        return false

    # 检查是否已在队列中或正在加载
    if scene_id == current_scene_id and _is_loading:
        push_warning("SceneLoader: Scene '%s' is already being loaded" % scene_id)
        return true

    if scene_id in _load_queue:
        push_warning("SceneLoader: Scene '%s' is already in queue" % scene_id)
        return true

    # 检查队列是否已满
    if _load_queue.size() >= MAX_QUEUE_SIZE:
        push_error("SceneLoader: Load queue is full (max %d)" % MAX_QUEUE_SIZE)
        load_failed.emit(scene_id, Error.QUEUE_FULL)
        return false

    # 加入队列
    _load_queue.append(scene_id)

    # 如果当前空闲，立即开始加载
    if current_stage == LoadingStage.IDLE:
        _process_queue()

    return true


## 获取当前加载状态
## 返回: 当前 LoadingStage 值
func get_current_stage() -> LoadingStage:
    return current_stage


## 获取当前加载进度
## 返回: 0-100 的进度值
func get_progress() -> int:
    return _current_progress


## 获取队列中的场景数量
## 返回: 队列长度（不含正在加载的）
func get_queue_size() -> int:
    return _load_queue.size()


## 取消当前加载（如果正在加载）
func cancel_loading() -> void:
    if _is_loading:
        _cleanup_loading_state()
        current_stage = LoadingStage.IDLE
        _is_loading = false
        load_failed.emit(current_scene_id, Error.TIMEOUT)


## 清除队列（取消所有待加载请求）
func clear_queue() -> void:
    _load_queue.clear()


# ==================== Loading Process ====================

func _process_queue() -> void:
    if _load_queue.is_empty():
        current_stage = LoadingStage.IDLE
        _is_loading = false
        return

    var scene_id: String = _load_queue.pop_front()
    _start_loading(scene_id)


func _start_loading(scene_id: String) -> void:
    current_scene_id = scene_id
    _is_loading = true
    current_stage = LoadingStage.LOADING_CONFIG
    _load_start_time = Time.get_ticks_msec()
    _last_progress_time = _load_start_time
    _current_progress = 0
    _using_default_config = false
    _using_fallback_background = false
    _using_silent_audio = false
    _loaded_resources.clear()

    # 重置资源加载跟踪
    _current_resource_path = ""
    _resource_progress[0] = 0.0

    # 立即报告进度 0
    load_progress_changed.emit(0)

    # 开始加载配置
    _load_config()


func _load_config() -> void:
    current_stage = LoadingStage.LOADING_CONFIG
    stage_completed.emit("loading_config")

    # 尝试从配置系统获取场景配置
    var config_loader := _get_config_loader()
    if config_loader == null:
        # 降级：使用默认配置
        push_warning("SceneLoader: Config loader not available, using default config for '%s'" % current_scene_id)
        _using_default_config = true
        current_config = _create_default_config(current_scene_id)
    else:
        current_config = config_loader.get_scene_config(current_scene_id)
        if current_config == null:
            # 配置文件不存在，使用默认配置
            push_warning("SceneLoader: Config not found for '%s', using default" % current_scene_id)
            _using_default_config = true
            current_config = _create_default_config(current_scene_id)

    # 更新进度到10%
    _update_progress(10)

    # 进入背景加载阶段
    _load_background()


func _create_default_config(scene_id: String) -> SceneConfig:
    var config := SceneConfig.new()
    config.scene_id = scene_id
    config.display_name = scene_id
    config.chapter = 1
    config.order = 1
    config.background_resource = ""  # 将使用纯色背景
    config.bgm_resource = ""         # 将使用静音
    config.ambient_resource = ""
    return config


func _load_background() -> void:
    current_stage = LoadingStage.LOADING_BACKGROUND
    stage_completed.emit("loading_background")

    var bg_path := current_config.background_resource

    if bg_path.is_empty():
        # 无背景配置，使用默认（将在初始化阶段创建纯色背景）
        _using_fallback_background = true
        _update_progress(40)
        _load_audio()
        return

    # 异步加载背景资源
    _start_resource_load(bg_path, func(success: bool):
        if not success:
            push_warning("SceneLoader: Failed to load background '%s', using fallback" % bg_path)
            _using_fallback_background = true
        _update_progress(40)
        _load_audio()
    )


func _load_audio() -> void:
    current_stage = LoadingStage.LOADING_AUDIO
    stage_completed.emit("loading_audio")

    var bgm_path := current_config.bgm_resource
    var ambient_path := current_config.ambient_resource

    # 异步加载 BGM
    if not bgm_path.is_empty():
        _start_resource_load(bgm_path, func(success: bool):
            if not success:
                push_warning("SceneLoader: Failed to load BGM '%s'" % bgm_path)
                _using_silent_audio = true

            # 继续加载环境音
            if not ambient_path.is_empty():
                _start_resource_load(ambient_path, func(ambient_success: bool):
                    if not ambient_success:
                        push_warning("SceneLoader: Failed to load ambient '%s'" % ambient_path)
                    _update_progress(70)
                    _initialize_scene()
                )
            else:
                _update_progress(70)
                _initialize_scene()
        )
    else:
        _using_silent_audio = true
        if not ambient_path.is_empty():
            _start_resource_load(ambient_path, func(ambient_success: bool):
                if not ambient_success:
                    push_warning("SceneLoader: Failed to load ambient '%s'" % ambient_path)
                _update_progress(70)
                _initialize_scene()
            )
        else:
            _update_progress(70)
            _initialize_scene()


func _start_resource_load(path: String, callback: Callable) -> void:
    # 检查文件是否存在
    if not ResourceLoader.exists(path):
        callback.call(false)
        return

    # 使用 Godot 的异步资源加载
    var error := ResourceLoader.load_threaded_request(path)
    if error != OK:
        push_warning("SceneLoader: Failed to start threaded load for '%s' (error: %d)" % [path, error])
        callback.call(false)
        return

    _current_resource_path = path

    # 等待加载完成
    await _wait_resource_load(callback)


func _wait_resource_load(callback: Callable) -> void:
    var path := _current_resource_path
    var start_time := Time.get_ticks_msec()

    while true:
        var status := ResourceLoader.load_threaded_get_status(path, _resource_progress)

        match status:
            ResourceLoader.THREAD_LOAD_LOADED:
                var resource := ResourceLoader.load_threaded_get(path)
                if resource != null:
                    _loaded_resources[path] = resource
                callback.call(true)
                return

            ResourceLoader.THREAD_LOAD_FAILED:
                push_warning("SceneLoader: Resource load failed for '%s'" % path)
                callback.call(false)
                return

            ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                # 检查超时
                if Time.get_ticks_msec() - start_time > TIMEOUT_MS:
                    push_warning("SceneLoader: Resource load timeout for '%s'" % path)
                    callback.call(false)
                    return
                # 等待下一帧继续检查
                await Engine.get_main_loop().process_frame

            _:
                # 未知状态
                await Engine.get_main_loop().process_frame


func _initialize_scene() -> void:
    current_stage = LoadingStage.INITIALIZING
    stage_completed.emit("initializing")

    # 创建降级背景（如果需要）
    if _using_fallback_background:
        _create_fallback_background()

    # 模拟初始化工作（实际游戏可能有更多初始化逻辑）
    await Engine.get_main_loop().process_frame

    # 检查最终超时
    if _check_timeout():
        return

    # 完成加载
    _update_progress(100)
    _complete_loading()


func _create_fallback_background() -> void:
    # 创建纯色黑色背景作为降级
    # 在实际实现中，这可能是一个 GradientTexture2D 或简单的 ColorRect 资源
    var gradient := Gradient.new()
    gradient.set_color(0, Color.BLACK)
    gradient.set_color(1, Color.BLACK)

    var gradient_texture := GradientTexture2D.new()
    gradient_texture.gradient = gradient
    gradient_texture.width = 1920
    gradient_texture.height = 1080

    _loaded_resources["fallback_background"] = gradient_texture


func _complete_loading() -> void:
    current_stage = LoadingStage.LOADED

    var scene_data := {
        "scene_id": current_scene_id,
        "config": current_config,
        "resources": _loaded_resources,
        "degraded": _using_default_config or _using_fallback_background or _using_silent_audio,
        "using_default_config": _using_default_config,
        "using_fallback_background": _using_fallback_background,
        "using_silent_audio": _using_silent_audio
    }

    stage_completed.emit("loaded")
    load_completed.emit(current_scene_id, scene_data)

    # 加载完成，处理队列中的下一个
    _is_loading = false
    _process_queue()


func _check_timeout() -> bool:
    var elapsed := Time.get_ticks_msec() - _load_start_time
    if elapsed > TIMEOUT_MS:
        push_error("SceneLoader: Loading timeout for scene '%s'" % current_scene_id)
        current_stage = LoadingStage.ERROR
        _cleanup_loading_state()
        load_failed.emit(current_scene_id, Error.TIMEOUT)
        _is_loading = false
        _process_queue()
        return true
    return false


func _cleanup_loading_state() -> void:
    _loaded_resources.clear()
    current_config = null
    _current_resource_path = ""
    _resource_progress[0] = 0.0


func _update_progress(stage_end_progress: int) -> void:
    _current_progress = stage_end_progress
    load_progress_changed.emit(_current_progress)
    _last_progress_time = Time.get_ticks_msec()


func _get_config_loader() -> SceneConfigLoader:
    # 在实际游戏中，这里可能从依赖注入或单例获取
    # 为了测试，我们返回 null 让调用方处理
    return null


# ==================== Progress Tracking ====================

## 手动更新进度（用于精细进度控制）
## 在资源加载过程中提供更细粒度的进度更新
func _update_loading_progress() -> void:
    if not _is_loading:
        return

    var now := Time.get_ticks_msec()
    if now - _last_progress_time < UPDATE_INTERVAL_MS:
        return

    # 检查超时
    if _check_timeout():
        return

    # 根据当前阶段计算进度
    var base_progress: int = 0
    var stage_progress: float = 0.0

    match current_stage:
        LoadingStage.LOADING_CONFIG:
            base_progress = 0
            stage_progress = 1.0  # 配置已加载完成

        LoadingStage.LOADING_BACKGROUND:
            base_progress = 10
            # 检查资源加载进度
            if _current_resource_path != "":
                var status := ResourceLoader.load_threaded_get_status(_current_resource_path, _resource_progress)
                if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
                    stage_progress = _resource_progress[0]
            else:
                stage_progress = 0.5  # 默认中间进度

        LoadingStage.LOADING_AUDIO:
            base_progress = 40
            stage_progress = 0.5  # 简化：音频阶段默认50%进度

        LoadingStage.INITIALIZING:
            base_progress = 70
            stage_progress = 0.5  # 初始化阶段默认50%进度

        _:
            return

    # 计算总进度
    var stage_weight: float
    match current_stage:
        LoadingStage.LOADING_CONFIG:
            stage_weight = CONFIG_WEIGHT
        LoadingStage.LOADING_BACKGROUND:
            stage_weight = BACKGROUND_WEIGHT
        LoadingStage.LOADING_AUDIO:
            stage_weight = AUDIO_WEIGHT
        LoadingStage.INITIALIZING:
            stage_weight = INIT_WEIGHT
        _:
            stage_weight = 0.0

    var progress := int(base_progress + stage_progress * stage_weight * 100)
    progress = clamp(progress, 0, 99)

    if progress != _current_progress:
        _current_progress = progress
        load_progress_changed.emit(progress)

    _last_progress_time = now
