# SpiritForest 第一人称改造详细设计规格

**文档类型**: 技术设计规格 (Technical Design Spec)  
**版本**: 1.0  
**日期**: 2026-07-01  
**目标场景**: SpiritForest (精灵森林)  
**改造范围**: 纯第一人称2D视角重构  
**基准分辨率**: 1920x1080 (16:9)  

---

## 1. 场景布局规格

### 1.1 第一人称视角定义

**视角规则**: 纯第一人称2D，玩家"看到"自己的手/法杖，但**看不到自身角色**。

```
视线方向 (玩家视角):
                    [天空/远景]
                         ↑
    [左边界] ← ───────────────────── → [右边界]
                    [中景层]
                         ↑
                    [近景层]
                         ↑
              [交互层 - 手部位置]
```

### 1.2 场景分层重构

| 层级 | Z-Index | 内容 | 视差系数 | 说明 |
|------|---------|------|----------|------|
| **Layer 5: UI层** | 100+ | HUD、Spark、对话框 | 0 | 固定屏幕空间 |
| **Layer 4: 前景层** | 50 | 树叶边缘、雾气 | 0.95 | 轻微随鼠标偏移 |
| **Layer 3: 交互层** | 30 | 手部/法杖、互动热点 | 0 | 玩家控制层 |
| **Layer 2: 近景层** | 20 | 近处树木、地面细节 | 0.3 | 慢速视差 |
| **Layer 1: 中景层** | 10 | TreeSpirit、魔法花、宝箱 | 0.15 | 中速视差 |
| **Layer 0: 远景层** | -20 | 远山、天空、远景树林 | 0.05 | 慢速视差 |

### 1.3 视场角(FOV)设定

| 参数 | 值 | 说明 |
|------|-----|------|
| 水平FOV | 90° | 标准宽屏视角，适配1920x1080 |
| 垂直FOV | 自动计算 | ~60° (由水平FOV和宽高比推导) |
| 画面比例 | 16:9 | 主目标，自适应其他比例 |
| 安全区域 | 中心80% | 关键UI不超出此区域 |

### 1.4 节点式移动系统

**概念**: 场景内预设5个观察节点，玩家点击热点区域后，执行"淡入淡出"过渡到新节点。

```
SpiritForest 节点布局 (俯视图):

    [节点A: 入口] ←→ [节点B: 大树前] ←→ [节点C: 花丛]
         ↓                ↓                ↓
    [节点D: 小溪] ←→ [节点E: 宝箱前]
```

**节点详细规格**:

| 节点 | 名称 | 位置(%) | 可交互元素 | 触发任务 |
|------|------|---------|------------|----------|
| A | 森林入口 | (50, 85) | 欢迎石碑、Spark首次出现 | greet_oakley |
| B | 大树前 | (50, 60) | TreeSpirit NPC | greeting_task |
| C | 魔法花丛 | (70, 55) | 红/蓝/黄魔法花 | activate_flowers |
| D | 小溪边 | (30, 65) | 发光蘑菇、流水 | nature_describe |
| E | 宝箱前 | (80, 70) | 宝箱、Oakley | open_chest |

**移动过渡参数**:
```gdscript
# FirstPersonNavigator.gd
const TRANSITION_DURATION: float = 0.8  # 秒
const TRANSITION_COLOR: Color = Color(0.1, 0.15, 0.1, 1.0)  # 深绿色淡出
const EASE_TYPE = Tween.EASE_IN_OUT
const TRANS_TYPE = Tween.TRANS_SINE
```

### 1.5 节点场景资源组织

```
SpiritForest_FirstPerson/  # 新场景文件
├── FPBackground/          # 远景层 (Layer 0)
│   ├── SkySprite
│   ├── MountainsSprite
│   └── FarTreesSprite
├── FPMidground/           # 中景层 (Layer 1)
│   ├── TreeSpiritNode/    # NPC节点
│   ├── FlowerRedNode/
│   ├── FlowerBlueNode/
│   ├── FlowerYellowNode/
│   └── TreasureChestNode/
├── FPNearground/          # 近景层 (Layer 2)
│   ├── GroundDetails/
│   └── NearTrees/
├── FPForeground/          # 前景层 (Layer 4)
│   ├── LeafOverlay/       # 边缘树叶装饰
│   └── MistEffect/
├── FPPlayer/              # 交互层 (Layer 3)
│   ├── HandsSprite/       # 手部/法杖
│   ├── WandGlow/          # 法杖光效
│   └── InteractionRay/    # 注视射线
├── FPNavigation/          # 导航热点
│   ├── NodeA_Hotspot
│   ├── NodeB_Hotspot
│   ├── NodeC_Hotspot
│   ├── NodeD_Hotspot
│   └── NodeE_Hotspot
└── FPHUD/                 # UI层 (Layer 5)
    ├── StarBar/
    ├── QuestTracker/
    ├── MicButton/
    └── SparkShoulder/
```

---

## 2. NPC交互规格

### 2.1 TreeSpirit NPC 第一人称呈现

**位置**: 固定于节点B (大树前)，距离玩家"2米"（屏幕高度60%位置）

| 属性 | 值 | 说明 |
|------|-----|------|
| 屏幕位置 | (50%, 60%) | 水平居中，垂直偏下 |
| 精灵尺寸 | 400x600px | 约占屏幕高度55% |
| 基础缩放 | 1.0 | 标准大小 |
| 眼神跟随 | 是 | 瞳孔跟随鼠标X轴偏移 |

**眼神跟随规则**:
```gdscript
# TreeSpiritController.gd
func _process(delta: float) -> void:
    var mouse_x = get_viewport().get_mouse_position().x
    var screen_center = get_viewport().size.x / 2
    var offset = (mouse_x - screen_center) / screen_center  # -1.0 到 1.0
    
    # 限制眼神偏移范围
    eye_pupil.position.x = lerp(eye_pupil.position.x, offset * 8.0, 0.1)
```

**TreeSpirit 动画状态**:

| 状态 | 动画 | 触发条件 | 时长 |
|------|------|----------|------|
| idle | 呼吸起伏 | 默认 | 循环 |
| greeting | 挥手+树叶飘落 | 玩家进入节点B | 2.0s |
| listening | 前倾+耳朵摆动 | 玩家语音输入中 | 直到ASR结束 |
| responding | 点头+光芒绽放 | TTS播放中 | 语音时长+0.5s |
| happy | 跳跃+花瓣散落 | 5星评价 | 3.0s |
| thinking | 歪头+眼睛闪烁 | 评估等待中 | 直到结果返回 |

### 2.2 对话触发距离

| NPC | 触发节点 | 触发条件 | 最小距离(像素) |
|-----|----------|----------|----------------|
| TreeSpirit | B | 进入节点B自动触发 | 0 (同节点) |
| Oakley | E | 数字任务阶段触发 | 0 (同节点) |
| Spark | 任意 | 干预/提示时飞入 | N/A (肩膀位) |

### 2.3 NPC视觉反馈规则

| 反馈类型 | 视觉表现 | 音频同步 |
|----------|----------|----------|
| **嘴型** | 播放TTS时按音素切换嘴型动画 | 与TTS精确同步 |
| **手势** | greeting/responding时随机播放手势动画 | 与对话内容匹配 |
| **表情** | 基于LXP分数切换表情精灵图 | 评估结果返回时切换 |
| **眼神** | 说话时瞳孔轻微抖动，强调时放大 | 与重读音节同步 |

---

## 3. Spark肩膀精灵改造规格

### 3.1 位置定义

**肩膀位置规则**: 固定于屏幕右下角，玩家"右肩"位置。

| 参数 | 值 | 说明 |
|------|-----|------|
| 锚点 | (0.9, 0.75) | 屏幕百分比坐标 |
| 像素坐标(1920x1080) | (1728, 810) | 右下角区域 |
| 精灵尺寸 | 120x160px | 缩小版Spark |
| Z-Index | 100 | 在所有UI之上 |

```gdscript
# SparkShoulderController.gd
const SHOULD_POSITION: Vector2 = Vector2(0.9, 0.75)  # 归一化坐标
const SPARK_SCALE: Vector2 = Vector2(0.25, 0.25)       # 缩放到25%

func _ready() -> void:
    _update_position()
    get_viewport().size_changed.connect(_update_position)

func _update_position() -> void:
    var viewport_size = get_viewport().get_visible_rect().size
    position = Vector2(
        viewport_size.x * SHOULD_POSITION.x,
        viewport_size.y * SHOULD_POSITION.y
    )
```

### 3.2 7状态系统适配

**肩膀Spark状态表** (继承自CoachOverlay，但尺寸和位置调整):

| 状态 | 优先级 | 肩膀位置动画 | 尺寸变化 | 气泡位置 |
|------|--------|--------------|----------|----------|
| `idle` | 0 | 呼吸微动 (±2px) | 1.0x | 无 |
| `thinking` | 1 | 亮度提升+思考符号 | 1.0x | 上方偏左 |
| `happy` | 2 | 跳跃庆祝 (向上15px) | 1.15x | 上方偏左 |
| `hint` | 3 | 缓慢浮动 (±3px) | 1.0x | 上方偏左 |
| `speaking` | 4 | 较快浮动 (±4px) | 1.0x | 上方偏左 |
| `enter` | 5 | 从右下飞入 | 0.8→1.0x | 无 |
| `exit` | 6 | 缩小消失 | 1.0→0.7x | 无 |

**气泡位置计算**:
```gdscript
# 气泡从Spark向左上方弹出
bubble_position = spark_position - Vector2(200, 50)
```

### 3.3 引导注视动画

**注视引导**: Spark通过身体朝向来引导玩家注视重点。

| 引导目标 | Spark动作 | 动画时长 |
|----------|-----------|----------|
| 左方物体 | 身体左转30°，手臂指向左 | 0.5s |
| 右方物体 | 身体右转30°，手臂指向右 | 0.5s |
| 上方物体 | 身体后仰，手指向上 | 0.5s |
| 中央物体 | 身体前倾，双手摊开 | 0.5s |

```gdscript
func guide_attention(target_direction: String) -> void:
    match target_direction:
        "left":
            _tween_body_rotation(-30.0, 0.5)
            _play_arm_animation("point_left")
        "right":
            _tween_body_rotation(30.0, 0.5)
            _play_arm_animation("point_right")
        "up":
            _tween_body_rotation(0.0, 0.5)
            _play_arm_animation("point_up")
        "center":
            _tween_body_rotation(0.0, 0.5)
            _play_arm_animation("open_hands")
```

---

## 4. HUD布局规格

### 4.1 UI元素坐标表

**基准分辨率**: 1920x1080

| 元素 | 锚点 | 像素坐标 | 尺寸 | 层级 |
|------|------|----------|------|------|
| **星星条** | (0.5, 0.08) | (960, 86) | 400x40 | HUDLayer |
| **任务追踪器** | (0.02, 0.15) | (38, 162) | 250x120 | HUDLayer |
| **语音按钮** | (0.5, 0.88) | (960, 950) | 80x80 | HUDLayer |
| **魔法指南针** | (0.92, 0.15) | (1766, 162) | 100x100 | HUDLayer |
| **Spark肩膀位** | (0.9, 0.75) | (1728, 810) | 120x160 | CoachLayer |
| **凝视提示** | 动态 | 目标物上方 | 自适应 | HUDLayer |
| **节点导航点** | 动态 | 屏幕边缘 | 40x40 | HUDLayer |

### 4.2 星星条样式调整

**第一人称版星星条**:

```gdscript
# StarBarFP.gd (继承自原有StarBar)
const BAR_WIDTH: float = 400.0
const BAR_HEIGHT: float = 40.0
const POSITION: Vector2 = Vector2(960, 86)  # 顶部居中

# 样式
const BAR_BG_COLOR: Color = Color(0.1, 0.1, 0.15, 0.8)
const BAR_FILL_GRADIENT: Gradient = preload("res://assets/ui/star_bar_gradient.tres")
const STAR_ICON_SIZE: Vector2 = Vector2(32, 32)
const STAR_SPACING: float = 8.0

# 动画
const FILL_DURATION: float = 0.5
const PULSE_DURATION: float = 0.3
```

**视觉设计**:
- 半透明弧形进度条，不遮挡场景
- 获得星星时从评分位置飞入
- 满20星时整条条发光震动

### 4.3 语音按钮样式

**按住说话按钮**:

| 状态 | 视觉表现 | 动画 |
|------|----------|------|
| 空闲 | 圆形按钮，绿色脉冲 | 呼吸动画 |
| 按住 | 圆形扩大+波纹扩散 | 按住时持续放大 |
| 录音中 | 红色脉冲+音波可视化 | 实时音量波形 |
| 处理中 | 旋转加载图标 | 旋转动画 |

```gdscript
# MicButtonFP.gd
const BUTTON_SIZE: float = 80.0
const POSITION: Vector2 = Vector2(960, 950)  # 底部中央

# 状态颜色
const COLOR_IDLE: Color = Color(0.2, 0.8, 0.4)
const COLOR_HOLDING: Color = Color(0.9, 0.7, 0.2)
const COLOR_RECORDING: Color = Color(0.9, 0.2, 0.2)
const COLOR_PROCESSING: Color = Color(0.4, 0.4, 0.9)
```

### 4.4 任务追踪器样式

| 属性 | 值 |
|------|-----|
| 位置 | 左上角，距离边缘20px |
| 背景 | 半透明圆角面板 |
| 宽度 | 250px |
| 高度 | 自适应 (每任务40px) |
| 字体 | 中文: 思源黑体, 英文: Nunito |
| 字号 | 任务名16px, 进度14px |

**显示内容**:
- 当前场景名称
- 进行中的主线任务 (图标+名称)
- 完成进度 (X/Y)
- 星星目标进度条

### 4.5 第一人称专属元素

**魔法指南针**:
- 位置: 右上角
- 功能: 显示当前节点方向
- 视觉: 旋转的魔法罗盘，当前节点发光

**凝视提示**:
- 位置: 可交互物体上方
- 触发: 鼠标悬停时显示
- 内容: 物品名称(中英文) + 语音图标
- 样式: 小气泡，2秒后淡出

**节点导航点**:
- 位置: 屏幕边缘指示未探索节点
- 视觉: 箭头图标+距离指示
- 交互: 点击快速移动到该节点

---

## 5. 交互流程(核心循环)

### 5.1 完整第一人称体验流程

```
[步骤1] 进入SpiritForest
    ↓
    场景加载 → 显示节点A(入口)
    ↓
    远景层淡入 → 中景层淡入 → 近景层淡入
    ↓
    Spark从肩膀位飞入 → 播放欢迎动画
    ↓
    气泡显示: "欢迎来到精灵森林！我是Spark，你的魔法伙伴！"
    ↓
    TTS播放

[步骤2] 首次问候任务
    ↓
    Spark引导注视: "看，那是TreeSpirit！我们去和他打招呼吧"
    ↓
    屏幕边缘显示导航点 → 点击或语音"Go"移动到节点B
    ↓
    过渡动画: 淡入淡出(0.8s) → 显示节点B
    ↓
    TreeSpirit播放greeting动画
    ↓
    NPC TTS: "Hello, young mage! I'm TreeSpirit. What's your name?"
    ↓
    语音按钮高亮脉冲 → 玩家按住说话
    ↓
    ASR识别 → LXP评估 → 星星反馈
    ↓
    星星飞向星星条 → TreeSpirit播放响应动画

[步骤3] 颜色魔法任务
    ↓
    Spark: "TreeSpirit教了你颜色魔法！我们去花丛试试"
    ↓
    导航到节点C → 显示红/蓝/黄三朵魔法花
    ↓
    Spark: "说出花的颜色来激活它们！Red、Blue、Yellow!"
    ↓
    玩家语音 → 正确颜色 → 对应花朵发光+粒子特效
    ↓
    三朵全激活 → 触发颜色任务完成

[步骤4] 数字任务
    ↓
    Spark: "小溪边有蘑菇，我们来数一数！"
    ↓
    导航到节点D → 显示发光蘑菇
    ↓
    Oakley出现: "Can you count how many mushrooms?"
    ↓
    玩家说"Seven" → 蘑菇发光 → 宝箱解锁提示

[步骤5] 宝箱与Badge
    ↓
    导航到节点E → 显示宝箱
    ↓
    玩家语音"Open" → 宝箱打开动画
    ↓
    星星达到阈值 → Badge解锁仪式
    ↓
    全屏动画: Badge旋转+光芒+Spark祝贺
    ↓
    解锁SpellLibrary导航选项

[步骤6] 会话结束
    ↓
    Spark: "今天学了很多！明天再来继续冒险！"
    ↓
    显示会话总结: 获得星星/X/LXP/金币
    ↓
    返回MainMenu或继续探索
```

### 5.2 视觉/音频/交互细节矩阵

| 步骤 | 视觉 | 音频 | 交互 |
|------|------|------|------|
| 进入场景 | 分层淡入、Spark飞入 | 森林环境音、Spark音效 | 自动播放 |
| 节点移动 | 淡入淡出过渡 | 脚步声/风声 | 点击热点或语音"Go" |
| NPC对话 | 眼神跟随、嘴型同步 | TTS、UI音效 | 自动播放 |
| 语音输入 | 麦克风波纹、按钮脉冲 | 录音提示音 | 按住说话 |
| 评估反馈 | 星星飞行动画 | 星级音效(chime) | 自动播放 |
| 任务完成 | 粒子特效、场景变化 | 完成音效 | 自动播放 |
| Badge解锁 | 全屏动画、光芒绽放 | 庆祝音乐 | 自动播放 |

### 5.3 语言学习目标结合

**四年级课标词汇覆盖**:

| 节点 | 词汇目标 | 句型目标 | 互动形式 |
|------|----------|----------|----------|
| B (TreeSpirit) | Hello, Hi, name | What's your name? | 自我介绍对话 |
| C (花丛) | Red, Blue, Yellow | What color...? | 颜色识别跟读 |
| D (小溪) | Mushroom, Seven | How many...? | 数字计数问答 |
| E (宝箱) | Open, Treasure | Can you...? | 祈使句使用 |

---

## 6. 技术实现要点

### 6.1 Godot 4.6 Camera2D配置

```gdscript
# FirstPersonCamera.gd
extends Camera2D

const BASE_ZOOM: Vector2 = Vector2(1.0, 1.0)
const SHAKE_DURATION: float = 0.3
const SHAKE_MAGNITUDE: float = 5.0

func _ready() -> void:
    # 第一人称不需要跟随玩家，固定视角
    position = Vector2(960, 540)  # 场景中心
    
    # 配置视差效果
    offset = Vector2.ZERO
    
    # 禁用边缘限制
    limit_smoothed = false

func play_transition_fade_out() -> void:
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, TRANSITION_DURATION * 0.4)

func play_transition_fade_in() -> void:
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, TRANSITION_DURATION * 0.4)

func play_shake() -> void:
    var tween = create_tween()
    for i in range(10):
        var offset = Vector2(
            randf_range(-SHAKE_MAGNITUDE, SHAKE_MAGNITUDE),
            randf_range(-SHAKE_MAGNITUDE, SHAKE_MAGNITUDE)
        )
        tween.tween_property(self, "offset", offset, 0.03)
    tween.tween_property(self, "offset", Vector2.ZERO, 0.05)
```

### 6.2 场景资源组织

**推荐的Node结构**:

```
SpiritForest_FirstPerson (Node2D)
├── ParallaxBackground
│   ├── ParallaxLayer (z=-20, motion_scale=0.05)  # 远景
│   ├── ParallaxLayer (z=10, motion_scale=0.15)   # 中景
│   └── ParallaxLayer (z=20, motion_scale=0.3)    # 近景
├── FPWorld (Node2D)
│   ├── NodeA_Area2D (入口热点)
│   ├── NodeB_TreeSpirit (NPC)
│   ├── NodeC_Flowers (魔法花)
│   ├── NodeD_Stream (小溪)
│   └── NodeE_Chest (宝箱)
├── FPPlayer (Node2D)
│   ├── HandsSprite (手部/法杖)
│   └── InteractionRay (RayCast2D)
├── CanvasLayer (HUD)
│   ├── StarBar
│   ├── QuestTracker
│   ├── MicButton
│   ├── MagicCompass
│   └── FPNavigator (节点导航UI)
└── CanvasLayer (Coach)
    └── SparkShoulder (肩膀精灵)
```

### 6.3 系统兼容性

| 系统 | 兼容性 | 需要修改 |
|------|--------|----------|
| quest-service | ✓ 完全兼容 | 无修改，API不变 |
| spirit-coach-service | ✓ 完全兼容 | 无修改，WebSocket协议不变 |
| reward-service | ✓ 完全兼容 | 无修改，事件监听不变 |
| assessment-service | ✓ 完全兼容 | 无修改，ASR→LLM流程不变 |
| voice-service | ✓ 完全兼容 | 无修改，VAD+ASR流程不变 |

### 6.4 新增/修改GDScript脚本清单

**新增脚本**:

| 脚本路径 | 功能 | 行数预估 |
|----------|------|----------|
| `assets/scripts/scenes/SpiritForestFPController.gd` | 场景主控制器 | 300 |
| `assets/scripts/components/FirstPersonNavigator.gd` | 节点导航 | 200 |
| `assets/scripts/components/SparkShoulder.gd` | 肩膀精灵 | 250 |
| `assets/scripts/components/FPInteractionRay.gd` | 注视交互 | 150 |
| `assets/scripts/components/MagicCompass.gd` | 魔法指南针 | 100 |
| `assets/scripts/ui/FPStarBar.gd` | 第一人称星星条 | 120 |
| `assets/scripts/ui/FPMicButton.gd` | 第一人称语音按钮 | 180 |
| `assets/scripts/ui/FPQuestTracker.gd` | 第一人称任务追踪 | 150 |

**修改脚本**:

| 脚本路径 | 修改内容 |
|----------|----------|
| `assets/scripts/components/CoachOverlay.gd` | 添加肩膀位置模式 |
| `assets/scripts/components/TreeSpirit.gd` | 添加眼神跟随、嘴型同步 |

---

## 7. 验收标准

### 7.1 原型完成判定条件

**功能验收**:
- [ ] 5个节点可正常导航，过渡动画流畅
- [ ] TreeSpirit眼神跟随鼠标X轴
- [ ] Spark固定在肩膀位置，7状态动画正常
- [ ] 语音按钮按住说话功能正常
- [ ] 星星条获得星星时飞行动画正常
- [ ] 魔法指南针显示当前节点方向

**性能验收**:
- [ ] 场景加载时间 < 3秒
- [ ] 过渡动画帧率稳定60fps
- [ ] P95端到端延迟 < 1.5s

### 7.2 儿童测试观察指标

| 指标 | 观察方法 | 通过阈值 |
|------|----------|----------|
| 理解节点导航 | 观察是否能自主移动 | >80%能成功导航 |
| 识别Spark位置 | 提问"Spark在哪里" | >90%指向右下 |
| 理解第一人称视角 | 观察是否尝试"找自己" | <20%有困惑行为 |
| 沉浸感 | 观察是否主动探索 | >70%尝试点击互动 |
| 挫败感 | 问卷"不想玩了"比例 | <10% |

### 7.3 通过/失败阈值

| 测试项 | 通过标准 | 失败标准 |
|--------|----------|----------|
| 节点导航系统 | 5/5节点可用，过渡流畅 | >1节点无法到达 |
| Spark肩膀位 | 位置正确，动画正常 | 位置偏差>10%或动画异常 |
| NPC交互 | 眼神跟随、嘴型同步正常 | 眼神不跟随或嘴型不同步 |
| HUD布局 | 所有元素位置正确 | 元素重叠或超出屏幕 |
| 儿童可理解性 | >80%测试儿童能理解 | <60%能理解 |
| 沉浸感 | >70%愿意继续探索 | <50%愿意继续 |

---

## 8. GDD文档更新清单

### 8.1 需要更新的GDD文档

| 文档 | 更新章节 | 更新内容 |
|------|----------|----------|
| `game-concept.md` | §3 Core Identity | 添加视角设计决策章节 |
| `game-concept.md` | §5 Core Loop | 更新微循环描述为第一人称视角 |
| `spirit-coach.md` | §3.2 CoachOverlay | 添加肩膀位置模式规格 |
| `core-loop.md` | §3.1 微循环 | 更新为第一人称交互流程 |

### 8.2 game-concept.md 新增章节草稿

```markdown
## 视角设计决策

### 决策背景
经过原型验证对比，确定采用**纯第一人称2D视角**：

### 对比方案

| 方案 | 优点 | 缺点 | 验证结果 |
|------|------|------|----------|
| **A: 纯第一人称2D** (选定) | 沉浸感强、Spark肩膀精灵更自然、专注语言学习 | 场景表达受限 | SpiritForest原型测试通过 |
| B: 第三人称侧视 | 场景表现丰富、儿童熟悉 | Spark位置尴尬、玩家关注角色而非语言 | 未通过 |
| C: 混合视角 | 两者兼顾 | 实现复杂、认知负担重 | 未采用 |

### 第一人称规格概要
- **视场**: 90°水平FOV，16:9画面比例
- **移动方式**: 节点式点击移动 + 淡入淡出过渡
- **Spark位置**: 固定屏幕右下角肩膀位置 (0.9, 0.75)
- **交互方式**: 注视+语音，无文字输入

### 参考游戏
- **风格参考**: Firewatch (环境叙事第一人称)
- **儿童适配**: 简化控制，语音为主，减少UI复杂度
```

---

## 附录A: 坐标速查表

### 1920x1080分辨率关键坐标

| 元素 | X | Y | 宽度 | 高度 |
|------|---|-----|------|------|
| 星星条中心 | 960 | 86 | 400 | 40 |
| 任务追踪器左上 | 38 | 162 | 250 | 120 |
| 语音按钮中心 | 960 | 950 | 80 | 80 |
| Spark肩膀位 | 1728 | 810 | 120 | 160 |
| 魔法指南针中心 | 1766 | 162 | 100 | 100 |
| TreeSpirit中心 | 960 | 648 | 400 | 600 |

### 节点热点坐标

| 节点 | 屏幕X% | 屏幕Y% | 像素X | 像素Y |
|------|--------|--------|-------|-------|
| A (入口) | 50% | 85% | 960 | 918 |
| B (大树) | 50% | 60% | 960 | 648 |
| C (花丛) | 70% | 55% | 1344 | 594 |
| D (小溪) | 30% | 65% | 576 | 702 |
| E (宝箱) | 80% | 70% | 1536 | 756 |

---

**文档完成** — 本规格可直接交付gameplay-programmer实施
