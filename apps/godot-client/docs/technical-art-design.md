# LinguaQuest RPG 技术美术设计文档

> Technical Art Design Document
> 版本: 1.0 | 日期: 2026-06-26

---

## 目录

1. [渲染/视觉管线](#1-渲染视觉管线)
2. [场景架构与转换系统](#2-场景架构与转换系统)
3. [UI/UX系统设计](#3-uiux系统设计)
4. [动画系统](#4-动画系统)
5. [资源管道与优化策略](#5-资源管道与优化策略)
6. [性能目标与优化](#6-性能目标与优化)
7. [音频-视觉集成点](#7-音频-视觉集成点)
8. [技术美术风格指南](#8-技术美术风格指南)
9. [视觉系统与后端集成](#9-视觉系统与后端集成)
10. [移动端/桌面适配策略](#10-移动端桌面适配策略)
11. [技术挑战与风险](#11-技术挑战与风险)

---

## 1. 渲染/视觉管线

### 1.1 渲染架构

**渲染方法**: Godot 4.6 Mobile 渲染器

```ini
[rendering]
renderer/rendering_method="mobile"
```

**设计理由**:
- 针对移动端优化，适合 iOS/Android 目标平台
- 支持 2D 光照和基本 Shader 效果
- 在低端设备上保持 60FPS

### 1.2 分层渲染管线

```
Layer 0: 背景层 (Background)
  - 静态场景背景图
  - 远景视差滚动元素
  - 无 Shader，纯 Sprite 渲染

Layer 1: 环境特效层 (Ambient)
  - 粒子效果（漂浮光点、花瓣）
  - 环境 Shader（微弱发光、波动）
  - 性能预算: 16 个粒子系统

Layer 2: 场景交互层 (Interactive)
  - NPC 精灵
  - 可交互物体（花朵、宝箱）
  - Shader 特效（触发时）

Layer 3: UI 层 (UI)
  - HUD（星星条、对话气泡）
  - 对话面板
  - CoachOverlay (Spark)
  - 输入面板

Layer 4: 特效覆盖层 (VFX Overlay)
  - 全屏转场效果
  - 星级评价动画
  - 解锁仪式特效
```

### 1.3 Shader 系统

**现有 Shader 列表**:

| Shader 名称 | 用途 | 复杂度 | 性能预算 |
|-------------|------|--------|----------|
| `spirit_glow.gdshader` | Spark 精灵发光 | Medium | 2.0ms/帧 |
| `magic_burst.gdshader` | 魔法爆发效果 | Medium | 2.5ms/帧 |
| `transition_wipe.gdshader` | 场景转场 | Low | 1.0ms/帧 |
| `ambient_particle.gdshader` | 环境粒子 | Low | 1.5ms/帧 |
| `star_trail.gdshader` | 星星拖尾 | High | 3.0ms/帧 |

**Shader 降级策略**（已实现于 `ShaderManager.gd`）:

```
Level 0 (正常): 全部 Shader 启用
Level 1 (警告): 禁用 star_trail，降低 ambient_particle 质量
Level 2 (严重): 禁用所有 Shader，使用 ColorRect 降级
```

### 1.4 VFX 对象池系统

**性能预算常量**（来自 `VFXManager.gd`）:

```gdscript
MAX_PARTICLES_PER_FRAME: int = 100
MAX_ACTIVE_TWEENS: int = 50
MAX_SHADERS_ANIMATED: int = 20
EFFECT_COOLDOWN_MS: int = 100
```

**对象池配置**:

```gdscript
INITIAL_PARTICLE_POOL_SIZE: int = 30
MAX_PARTICLE_POOL_SIZE: int = 100
INITIAL_SHADER_POOL_SIZE: int = 15
MAX_SHADER_POOL_SIZE: int = 50
```

---

## 2. 场景架构与转换系统

### 2.1 场景状态机

```
场景生命周期状态:
[IDLE] → [REQUESTED] → [EXITING] → [FADING_OUT] → [BLACK_SCREEN]
  → [UNLOADING] → [LOADING] → [FADING_IN] → [ENTERING] → [COMPLETED]
```

**各阶段时间预算**（来自 `SceneTransition.gd`）:

```gdscript
FADE_OUT_DURATION: float = 0.5s
BLACK_SCREEN_DURATION: float = 0.3s
FADE_IN_DURATION: float = 0.5s
ANIMATION_TOTAL: float = 1.3s
TRANSITION_TIMEOUT_MS: int = 5000ms
```

### 2.2 场景配置结构

每个场景 JSON 配置包含视觉相关字段:

```json
{
  "scene_id": "spirit_forest",
  "resources": {
    "textures": ["forest_bg.png", "forest_fg.png"],
    "audio": ["forest_ambient.ogg"],
    "shaders": ["spirit_glow", "ambient_particle"]
  },
  "transition_effect": {
    "shader": "transition_wipe",
    "duration": 0.3,
    "params": {"wipe_direction": "left_to_right"}
  },
  "entry_events": [
    {"type": "spawn_particle", "particle_type": "ambient_float_forest"}
  ]
}
```

### 2.3 场景资源加载策略

**预加载时机**:
- MainMenu 显示时预加载首个场景资源
- 当前场景游玩时后台加载下一场景

**内存预算**:
- 单场景纹理内存: <50MB
- 同时加载场景数: 最多 2 个（当前 + 下一个）
- 总纹理内存预算: <100MB

---

## 3. UI/UX 系统设计

### 3.1 UI 层级架构

```
CanvasLayer 0: 游戏世界层
  - 游戏场景内容

CanvasLayer 10: HUD 层
  - StarBar（星星进度条）
  - SessionTimer（会话计时器）
  - QuestTracker（任务追踪器）

CanvasLayer 20: 对话层
  - DialogueBox（对话气泡）
  - NPC 头像

CanvasLayer 30: Coach 层
  - CoachOverlay（Spark 精灵）
  - 提示气泡

CanvasLayer 40: 覆盖层
  - SpiritUnlockOverlay（解锁动画）
  - AchievementPanel（成就面板）

CanvasLayer 50: 转场层
  - SceneTransition（黑屏淡入淡出）
```

### 3.2 星星条 (StarBar) 视觉设计

**位置**: 屏幕顶部中央
**形态**: 弧形进度条，填满 20 颗星星后触发 Badge 解锁

**视觉状态映射**:

| 星星占比 | 视觉表现 | Spark 提示语 |
|---------|---------|-------------|
| 0-25% | 灰色底色，微弱发光 | "刚开始，加油！" |
| 25-50% | 金色填充 1/4，光点闪烁 | "已经四分之一啦！" |
| 50-75% | 金色填充过半，粒子增强 | "过半啦，继续！" |
| 75-100% | 金色填充 3/4，光晕增强 | "就差一点点，冲刺！" |
| >=100% | 全满彩虹色，震动特效 | "徽章解锁！太棒了！" |

**动画参数**（来自 `StarFlightAnimation.gd`）:

```gdscript
BEZIER_CONTROL_OFFSET: Vector2 = Vector2(0, -200)  # 抛物线高度
ROTATION: float = 720.0  # 旋转度数
FLY_DURATION: float = 0.8s
```

### 3.3 CoachOverlay (Spark) 状态系统

**7 状态显示层**（来自 `spirit-coach.md`）:

| 状态 | 优先级 | 视觉表现 | 触发条件 |
|------|--------|----------|----------|
| idle | 0 | 呼吸动画，轻微浮动 | 默认 |
| thinking | 1 | 思考动画，亮度提升 | 收到干预请求 |
| happy | 2 | 跳跃庆祝，缩放脉冲 | 连续正确/任务完成 |
| hint | 3 | 提示状态，缓慢浮动 | 显示沉默/错误提示 |
| speaking | 4 | 说话动画，较快浮动 | 播放 TTS 时 |
| enter | 5 | 飞入动画，透明度+缩放 | Spark 进入屏幕 |
| exit | 6 | 淡出动画，缩小消失 | Spark 离开屏幕 |

**状态切换规则**: 优先级门控，新状态优先级 >= 当前状态才允许切换

### 3.4 Tween 并发管理

**性能预算**（来自 `UITweenManager.gd`）:

```gdscript
MAX_ACTIVE_TWEENS: int = 50
```

**类别并发限制**:

```gdscript
"scene_transition": {"max": 1, "priority": "高"}    # 必须保证
"dialogue": {"max": 3, "priority": "高"}              # 气泡+文字+头像
"ui_feedback": {"max": 10, "priority": "中"}          # 按钮点击
"vfx": {"max": 20, "priority": "中"}                  # 星星飞行
"ambient": {"max": 16, "priority": "低"}              # 可降级
```

---

## 4. 动画系统

### 4.1 动画类型分类

| 动画类别 | 实现方式 | 性能预算 | 降级策略 |
|---------|---------|---------|----------|
| 角色动画 | SpriteFrames + AnimationPlayer | 30fps | 降低帧率至 15fps |
| UI 过渡 | Tween | 50 并发 | 跳过非关键动画 |
| 粒子效果 | GPUParticles2D | 100 粒子/帧 | 数量减半 |
| Shader 动画 | ShaderMaterial 参数动画 | 20 个/帧 | 禁用 Shader |
| 场景转场 | ColorRect + Shader | 独占 | 简化纯色淡入淡出 |

### 4.2 关键动画规范

**星星飞行动画**:
- 路径: 贝塞尔曲线（二次曲线）
- 旋转: 720 度
- 时长: 0.8 秒
- 缓动: Quad.InOut

**Spark 动画**:
- 呼吸动画: scale 1.0 → 1.05 → 1.0，周期 2 秒
- 飞入: 从屏幕边缘滑入 + 淡入，0.5 秒
- 跳跃庆祝: 弹跳 3 次，1 秒

**徽章解锁仪式**:
- 总时长: 30-60 秒（不可跳过）
- 包含: 全屏闪光 + Spark 祝贺 + Badge 旋转 + 奖励展示

### 4.3 动画缓动标准

| 动画类型 | 推荐缓动 | 说明 |
|---------|---------|------|
| UI 入场 | `CUBIC_OUT` | 快速到达，缓慢停止 |
| UI 退场 | `CUBIC_IN` | 缓慢开始，快速离开 |
| 反馈动画 | `BACK_OUT` | 轻微回弹，增强弹性感 |
| 循环动画 | `SINE_IN_OUT` | 平滑循环，无突兀感 |
| 粒子动画 | `LINEAR` | 物理模拟，线性更自然 |

---

## 5. 资源管道与优化策略

### 5.1 纹理规范

**分辨率标准**:
- 背景图: 1920×1080（适配 16:9）
- NPC 精灵: 256×256（单帧）
- UI 元素: 根据功能，最大 512×512
- 粒子贴图: 64×64 或更小

**格式要求**:
- 所有纹理: PNG（无损）或 WebP（有损压缩）
- 移动端: 启用纹理压缩（ETC2/ASTC）
- 导入设置: Filter = Nearest（像素风）或 Linear（平滑）

### 5.2 Shader 资源管理

**预加载策略**:

```gdscript
func _ready() -> void:
    _preload_all_shaders()
    _prewarm_material_pools()
```

**材质池配置**:

```gdscript
POOL_INITIAL_SIZE: int = 5  # 每类 Shader 材质初始数量
```

### 5.3 音频视觉同步

**唇形同步 (Lip Sync)**:
- 使用 TTS 音频的振幅数据驱动 NPC 嘴巴动画
- 简化方案: 说话时显示"说话"精灵帧，静音时切回"空闲"
- 高级方案: 分析音频频谱驱动嘴型混合

**关键时间点**:

```gdscript
npc_response_delay_ms: int = 500   # NPC 响应延迟
silence_threshold_s: int = 10      # 沉默检测阈值
```

---

## 6. 性能目标与优化

### 6.1 性能预算

| 指标 | 目标 | 最低接受值 | 监控方法 |
|------|------|-----------|----------|
| FPS | 60 | 30 | PerformanceMonitor |
| 帧时间 | 16.6ms | 33.3ms | 内置 Profiler |
| 内存 | <200MB | <300MB | OS 监控 |
| 加载时间 | <3 秒 | <5 秒 | 自定义计时 |
| Shader 编译 | <100ms | <200ms | 首次使用计时 |

### 6.2 降级策略层级

```
Level 0 (正常):
  - 全部特效启用
  - 60FPS 目标

Level 1 (粒子减少):
  - 环境粒子数量减半
  - 禁用复杂粒子效果

Level 2 (Shader 禁用):
  - 禁用所有自定义 Shader
  - 使用 ColorRect 降级
  - 保持 Tween 动画

Level 3 (Tween 简化):
  - 简化 Tween 动画
  - 仅保留必要反馈
  - 目标 30FPS
```

### 6.3 性能监控实现

**PerformanceMonitor 配置**:

```gdscript
update_interval_ms: int = 500
fps_threshold_critical: float = 30.0
fps_threshold_warning: float = 45.0
fps_threshold_notice: float = 55.0
HISTORY_SIZE: int = 10  # 滑动窗口大小
```

---

## 7. 音频-视觉集成点

### 7.1 语音交互管线

```
[玩家语音]
  → [VoicePipeline VAD 检测]
    → [voice-service ASR]
      → [dialogue-service LLM 评估]
        → [LXP 计算 + 星级映射]
          → [视觉反馈]:
              - 星星飞行动画 (StarFlightAnimation)
              - 星星条增长 (StarBar)
              - Spark 反馈 (CoachOverlay)
              - 场景特效 (魔法花绽放等)
        → [TTS 响应]
          → [NPC 嘴唇动画同步]
```

### 7.2 视觉反馈触发点

| 后端事件 | 视觉反馈 | 优先级 |
|---------|---------|--------|
| ASR 结果返回 | 录音面板关闭动画 | 高 |
| 星级计算完成 | 星星飞行动画 | 高 |
| 星星累积更新 | 星星条增长 + 震动 | 高 |
| Badge 解锁 | 全屏仪式动画 | 高 |
| Spark 干预 | CoachOverlay 状态切换 | 中 |
| 场景切换 | 转场 Shader 效果 | 高 |

### 7.3 延迟预算

**端到端延迟**（来自 `core-loop.md`）:
- 目标: P95 < 1.5 秒
- 分解:
  - VAD 检测: 50-100ms
  - ASR (Whisper): 300-800ms
  - LLM 评估: 200-500ms
  - TTS: 200-400ms
  - 网络往返: 100-200ms

**视觉延迟补偿**:
- 显示加载动画覆盖网络延迟
- 本地预测: 录音停止后立即播放"思考中"动画

---

## 8. 技术美术风格指南

### 8.1 色彩系统

**主色调**:
- 魔法主题: 深紫 `#4A148C` + 金色 `#FFD700`
- 自然主题: 森林绿 `#2E7D32` + 天蓝 `#4FC3F7`
- 星星系统: 金黄 `#FFC107` → 彩虹渐变（5 星时）

**星星色彩映射**:

| 星级 | 主色 | 发光色 | 粒子色 |
|------|------|--------|--------|
| 1 星 | `#9E9E9E` | 无 | `#BDBDBD` |
| 2 星 | `#FFC107` | `#FFECB3` | `#FFE082` |
| 3 星 | `#FFB300` | `#FFECB3` | `#FFD54F` |
| 4 星 | `#FF8F00` | `#FFE082` | `#FFCA28` |
| 5 星 | 彩虹渐变 | `#FFFFFF` | 多色闪烁 |

### 8.2 视觉语言

**魔法能量表达**:
- 1-2 星: 微弱发光，暗淡色调
- 3 星: 明亮金色，标准发光
- 4 星: 彩虹拖尾，强烈光晕
- 5 星: 全屏闪光，粒子爆发

**UI 反馈强度**:
- 轻微: 透明度变化，位置微调
- 中等: 缩放脉冲，颜色变化
- 强烈: 震动效果，粒子爆发，Shader 特效

### 8.3 字体规范

**中文显示**:
- 主要: Noto Sans CJK SC（思源黑体）
- 标题: 圆润风格字体
- 字号: 最小 16px（适配儿童阅读）

**英文显示**:
- 对话文本: 清晰无衬线字体
- 关键词: 加粗 + 颜色高亮

---

## 9. 视觉系统与后端集成

### 9.1 WebSocket 事件处理

**视觉相关事件类型**:

```gdscript
# 来自 spirit-coach-service
CoachIntervention:
  trigger: 'wake' | 'error' | 'silence'
  emotion: 'happy' | 'thinking' | 'hint'
  should_tts: bool

# 来自 quest-service
QuestStatusEvent:
  quest_id: String
  new_status: 'completed' | 'in_progress'
  stars_earned: int
```

### 9.2 数据流映射

```
后端评估结果 → 前端视觉映射:

LXP 分数 (0-100)
  → 星级 (1-5)
    → 星星飞行动画参数
    → Spark 反馈表情
    → 粒子效果强度

任务完成事件
  → Badge 解锁检查
    → 解锁动画触发
    → 场景状态更新

ASR 失败事件
  → 示范模式 UI
    → 录音按钮状态变化
    → 提示气泡显示
```

---

## 10. 移动端/桌面适配策略

### 10.1 分辨率适配

**目标分辨率**:
- 手机: 1080×1920 (9:16)
- 平板: 1536×2048 (3:4)
- 桌面: 1920×1080 (16:9)

**适配策略**:

```gdscript
[display]
window/stretch/mode="canvas_items"
```

- UI 锚点使用相对位置
- 背景图采用"覆盖"模式填充
- 关键交互元素保持在安全区域内（屏幕中央 80%）

### 10.2 性能分级

**设备等级检测**:

```gdscript
# 基于 FPS 自动检测
if Engine.get_frames_per_second() < 45:
    PerformanceMonitor.trigger_degradation(LEVEL_1)
```

**分级配置**:

| 等级 | 设备示例 | Shader | 粒子 | Tween |
|------|---------|--------|------|-------|
| 高端 | iPhone 14+ | 完整 | 100% | 完整 |
| 中端 | Android 中端 | 简化 | 70% | 完整 |
| 低端 | Android 入门 | 禁用 | 30% | 简化 |

### 10.3 触摸优化

- **最小点击区域**: 44×44px
- **手势支持**: 简单的点击和滑动
- **视觉反馈**: 按钮按下状态必须明显

---

## 11. 技术挑战与风险

### 风险 1: ASR 识别率影响视觉反馈及时性

**影响**: 网络延迟或识别失败导致视觉反馈滞后，破坏沉浸感

**解决方案**:
- 本地预测动画: 录音停止后立即播放"思考中"动画
- 后端校正: 识别失败时切换示范模式 UI
- 超时保护: 3 秒无响应自动触发 Spark 鼓励

### 风险 2: 低端设备 Shader 性能

**影响**: Shader 编译卡顿、帧率下降

**解决方案**:
- 多级降级策略（4 级）
- ColorRect 降级方案兜底
- Shader 预热机制避免首次使用卡顿

### 风险 3: 儿童注意力窗口与场景时长匹配

**影响**: 20-25 分钟注意力窗口，场景过长导致疲劳

**解决方案**:
- 场景设计控制在 8-12 分钟
- 强制课间休息机制
- SessionTimer 视觉提醒（星星条颜色渐变）

### 风险 4: 跨会话状态同步的视觉连续性

**影响**: 重新加载后丢失进度感

**解决方案**:
- 加载画面显示上次进度
- Spark 问候语回顾上次进度
- 本地缓存关键视觉状态

---

## 相关系统文件

| 系统 | 文件路径 |
|------|---------|
| Shader 管理 | `assets/scripts/autoload/ShaderManager.gd` |
| VFX 管理 | `assets/scripts/autoload/VFXManager.gd` |
| Tween 管理 | `assets/scripts/autoload/UITweenManager.gd` |
| 性能监控 | `assets/scripts/components/PerformanceMonitor.gd` |
| 场景转换 | `assets/scripts/core/scene_transition.gd` |
| 星星动画 | `assets/scripts/ui/StarFlightAnimation.gd` |
| Coach 覆盖层 | `assets/scripts/components/CoachOverlay.gd` |
| 对话系统 | `assets/scripts/autoload/DialogueBox.gd` |

## 参考设计文档

- `design/gdd/game-concept.md` — 游戏概念
- `design/gdd/core-loop.md` — 核心循环
- `design/gdd/quest-system.md` — 任务系统
- `design/gdd/star-economy.md` — 星星经济
- `design/gdd/spirit-coach.md` — 精灵教练
- `design/gdd/lxp-system.md` — LXP 系统
