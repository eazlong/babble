# LinguaQuest RPG 前端架构设计

## 一、架构层次图

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              CANVAS LAYER STACK                          │
│  (Layer 0: Scene | Layer 1: HUD | Layer 2: Dialogue | Layer 3: Overlay)    │
├─────────────────────────────────────────────────────────────────────────┤
│  Layer 3: OverlayCanvasLayer (z=30)                                     │
│    ├─ CoachOverlay (Spark 精灵, 7状态优先级门控)                           │
│    ├─ SpiritUnlockOverlay (词灵解锁仪式)                                  │
│    ├─ AchievementPanel (徽章展示)                                        │
│    ├─ SceneModeSelector (场景选择器)                                      │
│    └─ RewardAnimation (奖励动画)                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  Layer 2: DialogueCanvasLayer (z=20)                                     │
│    ├─ DialogueBox (NPC 对话气泡, TTS同步)                                │
│    ├─ VoiceInputIndicator (语音输入指示器)                                │
│    └─ StarRatingPanel (1-5星评价动画)                                    │
├─────────────────────────────────────────────────────────────────────────┤
│  Layer 1: HUDCanvasLayer (z=10)                                          │
│    ├─ GameHUD (星星条进度、任务列表)                                       │
│    ├─ QuestTracker (日常/主线任务进度)                                     │
│    ├─ BreakReminder (课间休息提示)                                        │
│    └─ SessionTimer (会话时长监控)                                        │
├─────────────────────────────────────────────────────────────────────────┤
│  Layer 0: SceneCanvasLayer (z=0)                                         │
│    ├─ SceneController (SpiritForest/SpellLibrary/RainbowGarden)          │
│    ├─ InteractiveObjects (MagicFlower/TreasureChest/EasterEgg)        │
│    ├─ NPCController (场景NPC动画)                                        │
│    └─ ParticleLayer (环境粒子效果)                                       │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                         AUTOLOAD SINGLETONS (全局系统)                    │
├─────────────────────────────────────────────────────────────────────────┤
│  UIFramework ───────┐                                                    │
│  GameManager ───────┼───► 应用状态管理 (玩家数据、场景进度)                 │
│  SceneManagementSystem┘                                                    │
├─────────────────────────────────────────────────────────────────────────┤
│  VFXManager ─────────► 对象池化特效系统 (粒子/Shader/Tween)                 │
│  AudioManager ──────► 音效/TTS播放管理                                    │
│  DialogueManager ─────► 对话状态机 (AWAITING_RESPONSE → PROCESSING)       │
│  CoachClient ────────► WebSocket连接spirit-coach-service                   │
│  QuestWebSocket ────► 任务系统实时通信                                    │
│  VoicePipeline ──────► VAD→ASR→LLM→TTS管线                               │
├─────────────────────────────────────────────────────────────────────────┤
│  SaveSystem ────────► 本地存档 + Supabase同步                             │
│  PerformanceMonitor ─► FPS监控，触发动态降级                               │
│  SpiritDatabase ────► 词灵数据查询                                        │
│  SpiritCollectionManager ─► 词灵收集系统                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 二、关键系统模块定义

### 2.1 视觉系统架构

| 模块 | 职责 | 依赖关系 |
|------|------|---------|
| **VFXManager** (autoload) | 对象池化粒子/Shader/Tween管理，3级性能降级 | PerformanceMonitor |
| **ParticleEffect** (component) | 场景内交互反馈（花朵绽放、宝箱解锁） | VFXManager |
| **ShaderPipeline** | 魔法光晕/过渡擦除/精灵发光材质 | GPU Particles2D |
| **SpriteAnimation** | NPC/Spark精灵动画状态机 | AnimatedSprite2D |

**性能预算 (Per-Frame)**:
- MAX_PARTICLES_PER_FRAME: 100
- MAX_ACTIVE_TWEENS: 50
- MAX_SHADERS_ANIMATED: 20

**降级策略**:
```gdscript
enum DegradationLevel {
    NONE = 0,              # 全特效
    LEVEL_1_REDUCE_PARTICLES = 1,  # FPS<55: 粒子减半
    LEVEL_2_DISABLE_SHADERS = 2,   # FPS<45: 禁用Shader
    LEVEL_3_SIMPLIFY_TWEENS = 3    # FPS<30: 仅基础Tween
}
```

---

### 2.2 UI系统架构

| 模块 | 职责 | 输入信号 |
|------|------|---------|
| **UIFramework** (autoload) | 4层CanvasLayer管理、页面栈(Push/Pop)、遮罩控制 | - |
| **GameHUD** (Layer 1) | 星星条(弧形进度)、任务追踪、会话计时 | StarAccumulationUpdate |
| **DialogueBox** (Layer 2) | NPC对话气泡、TTS同步播放、打字机效果 | DialogueManager |
| **CoachOverlay** (Layer 3) | Spark 7状态显示、优先级门控、气泡TTL | CoachIntervention |
| **RewardAnimation** (Layer 3) | Badge解锁仪式、粒子爆发、音效同步 | BadgeUnlockEvent |

**动画系统**:
- **Tween引擎**: Godot原生Tween，支持EASE_IN_OUT/TRANS_BACK
- **页面转场**: Push从右侧滑入(0.3s)，Pop从右侧滑出(0.25s)
- **星星飞行动画**: 评分点→星星条，带拖尾粒子

**响应式布局策略**:
```gdscript
# 基础分辨率: 1920x1080
# 缩放模式: canvas_items (保持宽高比)
# 安全区域: 距离边缘5% viewport尺寸
var margin_x = viewport_size.x * 0.05
var margin_y = viewport_size.y * 0.05
```

---

### 2.3 场景管理架构

| 模块 | 职责 | 状态流转 |
|------|------|---------|
| **SceneManagementSystem** | 场景进入/退出14步流程、资源卸载 | SceneStateMachine |
| **SceneConfig** | 场景配置数据(NPC列表、背景、解锁条件) | JSON配置 |
| **SceneLoader** | 异步资源加载、进度回调 | ResourceLoader |
| **SceneTransition** | 淡入淡出/擦除过渡效果 | Shader |

**场景切换14步流程** (ADR-0006):
```
1. Validate State (IDLE only)
2. Validate scene_id exists
3. Validate unlocked
4. Exit current scene (if ACTIVE)
5. State → TRANSITIONING_IN
6. Block input
7. Load resources
8. Register primary NPC
9. Trigger entry_events
10. Emit scene_entering
11. Transition animation
12. Unblock input
13. State → ACTIVE
14. Emit scene_entered + scene_name_display
```

**资源卸载预算**:
| 阶段 | 预算 | 超时阈值 |
|------|------|---------|
| Saving state | 100ms | 150ms |
| Stopping audio | 50ms | 150ms |
| Releasing background | 100ms | 150ms |
| Cleaning nodes | 100ms | 150ms |
| Unloading resources | 100ms | 150ms |

---

### 2.4 资源管线

| 模块 | 职责 | 存储路径 |
|------|------|---------|
| **ResourcePool** | 粒子/Shader/Tween对象池 | VFXManager内部 |
| **AssetLibrary** | 精灵图、背景、音效资源 | res://assets/ |
| **ConfigLoader** | 场景配置、任务数据、LXP阈值 | res://assets/data/ |
| **SaveSystem** | 玩家进度本地存储 + 云端同步 | user:// + Supabase |

**Art资产组织结构**:
```
assets/
├── sprites/
│   ├── characters/          # NPC精灵图
│   ├── spirits/            # 词灵精灵
│   └── ui/                 # UI元素
├── backgrounds/            # 场景背景(分层)
├── audio/
│   ├── bgm/               # 背景音乐
│   ├── sfx/               # 音效
│   └── voice/             # TTS缓存
├── resources/
│   ├── shaders/           # Shader材质
│   │   ├── effects/      # 魔法特效
│   │   └── spirit/       # 精灵发光
│   ├── vfx_presets/       # 粒子预设
│   ├── scene_configs/     # 场景配置JSON
│   └── fonts/            # 字体资源
└── data/                  # 游戏数据
    ├── quest_config.json
    ├── star_economy.json
    └── lxp_config.json
```

---

## 三、实现建议 (Godot 4.6 最佳实践)

### 3.1 视觉系统

**Shader系统规划**:
```gdscript
# 推荐Shader类型
1. spirit_glow.gdshader    # 精灵轮廓发光 (简单)
2. magic_burst.gdshader    # 魔法爆发波纹 (中等)
3. transition_wipe.gdshader  # 场景过渡擦除 (简单)
4. star_trail.gdshader     # 星星拖尾 (可选)
```

**VFX分层管理**:
- **Layer 0**: 环境粒子(萤火虫、落叶) - 始终开启
- **Layer 1**: 交互反馈(花朵绽放) - 可降级
- **Layer 2**: UI特效(星星飞行) - 优先保证
- **Layer 3**: 仪式特效(Badge解锁) - 全特效

### 3.2 UI系统

**CanvasLayer层级严格执行ADR-0003**:
```gdscript
enum LayerIndex {
    SCENE = 0,      # z=0
    HUD = 1,        # z=10
    DIALOGUE = 2,   # z=20
    OVERLAY = 3     # z=30
}
```

**Tween使用模式**:
```gdscript
# 推荐: 链式调用，避免内存泄漏
var tween = create_tween()
tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
tween.tween_property(target, "position:x", 0.0, 0.3)
tween.tween_callback(_on_complete)

# 禁止: 不保存Tween引用导致GC问题
create_tween().tween_property(...)  # 可能被GC
```

### 3.3 场景管理

**异步加载模式**:
```gdscript
# 场景资源预加载
ResourceLoader.load_threaded_request(scene_path)
# 在过渡动画中检查进度
while ResourceLoader.load_threaded_get_status(scene_path) == THREAD_LOADING:
    await get_tree().process_frame
```

**内存管理**:
- 场景退出时调用 `queue_free()` 而非 `free()`
- 纹理资源使用 `ResourceLoader` 缓存，场景切换时释放
- 音频流使用 `AudioStreamPlayer` 池，避免频繁创建

### 3.4 性能优化

**关键指标监控**:
```gdscript
# PerformanceMonitor (已存在)
var current_fps: float = Engine.get_frames_per_second()
var draw_calls: int = RenderingServer.get_rendering_info(
    RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
)
```

**移动端适配**:
- 渲染方法: Mobile (已配置)
- 粒子数量: 移动端减半
- Shader复杂度: 移动端禁用复杂Shader

---

## 四、技术风险点 + 缓解策略

| 风险 | 影响 | 缓解策略 |
|------|------|---------|
| **ASR延迟>1.5s** | 破坏核心循环沉浸感 | 本地VAD+动画占位，异步评估结果到达后补播放 |
| **粒子特效过多导致掉帧** | 儿童设备性能差异大 | VFXManager 3级降级策略，FPS<55自动降级 |
| **场景切换内存泄漏** | 长时间游戏崩溃 | SceneManagementSystem 14步卸载流程，预算检查 |
| **WebSocket重连期间Spark干预丢失** | 学习支持中断 | CoachClient本地缓存最后5条干预，重连后补发 |
| **Tween并发导致内存泄漏** | 游戏卡顿 | 所有Tween保存引用，状态切换时_kill_all_tweens() |
| **中文CJK字体渲染** | 内存占用大 | UIFramework统一加载STHeiti.ttc，仅覆盖默认字体 |
| **星星条动画与逻辑不同步** | 视觉反馈错误 | StarEconomy事件驱动，动画完成后才更新数据 |
| **多分辨率适配** | UI错位 | CanvasLayer+全屏Control，基于viewport比例定位 |

---

## 五、系统交互图

### 5.1 30秒微循环

```
┌────────────────────────────────────────────────────────────────┐
│                         30秒微循环                              │
│  VoicePipeline ──► AssessmentService ──► StarEconomy          │
│       │                    │                    │              │
│       │                    ▼                    ▼              │
│       │            LXP Score (0-100)    Stars (1-5)           │
│       │                    │                    │            │
│       ▼                    ▼                    ▼              │
│  DialogueManager ◄── VFXManager.play_magic_activation()      │
│       │                                                        │
│       ▼                                                        │
│  DialogueBox (TTS播放) ◄── CoachOverlay (干预提示)              │
│                      (优先级门控: speaking > hint > idle)      │
└────────────────────────────────────────────────────────────────┘
```

### 5.2 场景切换流程

```
┌────────────────────────────────────────────────────────────────┐
│                        场景切换流程                            │
│  SceneManagementSystem.enter_scene()                           │
│    ├──► SceneStateMachine: UNINITIALIZED → TRANSITIONING_IN    │
│    ├──► 资源预加载 (异步)                                       │
│    ├──► VFXManager.play_ambient_float() [环境粒子]             │
│    ├──► AudioManager.play_bgm() [场景音乐]                     │
│    └──► SceneStateMachine: → ACTIVE                            │
│           └──► SceneController._on_scene_active()              │
│                  └──► NPCController.spawn_primary_npc()        │
└────────────────────────────────────────────────────────────────┘
```

---

## 六、文件位置汇总

| 架构模块 | 关键文件 |
|---------|---------|
| UI框架 | `/assets/scripts/ui/framework/ui_framework.gd` |
| 场景管理 | `/assets/scripts/core/scene_management_system.gd` |
| VFX系统 | `/assets/scripts/autoload/VFXManager.gd` |
| Spark显示 | `/assets/scripts/components/CoachOverlay.gd` |
| 对话系统 | `/assets/scripts/autoload/DialogueManager.gd` |
| 游戏配置 | `/assets/resources/scene_configs/` |
| Shader | `/assets/resources/shaders/` |
| VFX预设 | `/assets/resources/vfx_presets/` |

---

## 七、下一步计划

### 7.1 子系统详细设计（待补充）
- **Shader系统详细设计** - 每个Shader的技术实现细节
- **UI动画规范** - Tween时间曲线、过渡效果库
- **粒子特效预设库** - 每个场景的标准粒子配置

### 7.2 实现验证
- 对照现有代码验证架构一致性
- 补充缺失的Autoload Singletons
- 优化现有CanvasLayer层级

---

此架构设计已完全对齐现有GDD文档和Godot 4.6实现，可直接指导后续开发。