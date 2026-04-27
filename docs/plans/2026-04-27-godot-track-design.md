# Godot 轨道设计方案

**文档编号**：LQ-GODOT-001
**版本**：1.0
**日期**：2026年4月27日
**状态**：已确认

---

## 概述

为 LinguaQuest RPG 项目建立 Godot 4.3 并行开发轨道，与现有 CocosCreator 轨道并行开发至 Phase 2 里程碑（语音交互管线 + 基础对话系统），届时进行技术评估对比，选择主轨道继续 MVP 开发。

---

## 目标

- **目的**：技术评估对比，选择最适合本项目的游戏引擎
- **评估点**：Phase 2 完成时（约4-5周）
- **对比维度**：语音交互性能、跨平台能力、开发效率、AI集成复杂度、团队适配度、扩展性

---

## 项目结构

```
apps/
├── game-creator/          # CocosCreator 轨道（现有）
└── godot-client/          # Godot 轨道（新建）
    ├── project.godot      # Godot 4.3 项目文件
    ├── assets/
    │   ├── scenes/
    │   │   ├── MainMenu.tscn
    │   │   └── SpiritForest.tscn
    │   ├── scripts/
    │   │   ├── autoload/           # 全局单例
    │   │   ├── components/         # 组件脚本
    │   │   └── utils/              # 工具类
    │   ├── resources/
    │   │   ├── sprites/
    │   │   ├── audio/
    │   │   └── fonts/
    │   └── addons/                 # Godot 插件
    ├── export_presets.cfg
    └── README.md
```

---

## 核心场景设计

### 1. MainMenu.tscn

**功能**：
- SpiritCoach（精灵教练）飞入动画
- 精灵教练主动询问用户基本信息
- 语言选择后自动进入 SpiritForest，无需点击开始按钮

**结构**：
```
MainMenu (CanvasLayer)
├── Background (TextureRect)
├── TitleLabel (Label)
├── CoachOverlay (Control)
│   ├── CoachSprite (AnimatedSprite2D)
│   └── DialogueBubble (Panel)
│       └── DialogueText (RichTextLabel)
├── LangPanel (Control)
│   ├── LangZhButton (Button)
│   └── LangEnButton (Button)
└── VersionLabel (Label)
```

**流程**：
```
场景加载 → 精灵飞入动画（4秒）→ 显示欢迎语 + TTS
         → LangPanel 滑入 → 用户选择语言 → 精灵确认
         → 自动进入 SpiritForest
```

---

### 2. SpiritForest.tscn

**功能**：
- 1 个 NPC（精灵教练 Spark）
- 玩家可移动探索
- 全程语音交互对话

**结构**：
```
SpiritForest (Node2D)
├── Background (TextureRect)
├── Player (CharacterBody2D)
├── SparkNPC (StaticBody2D)
│   ├── Sprite (AnimatedSprite2D)
│   └── DialogueTrigger (Area2D)
├── DialogueBox (CanvasLayer)
│   ├── DialoguePanel
│   ├── NPCNameLabel
│   ├── DialogueText
│   └ VoiceIndicator
└── BGMPlayer (AudioStreamPlayer)
```

---

## 语音交互管线

### 交互模式

全程语音交互，自动触发：
- NPC 提问后 → 自动开启语音监听
- VAD 检测玩家说话开始/结束
- 无需手动点击按钮

### 模块设计

#### HybridAPI.gd（全局单例）

```gdscript
func ping_services() -> void
func synthesize_tts(text, voice_id, lang) -> Dictionary
func recognize_speech(audio_data, lang) -> Dictionary
func send_dialogue(user_text, npc_id, context) -> Dictionary
func process_voice_dialogue(audio_data, npc_id, lang) -> Dictionary
```

#### VoicePipeline.gd（全局单例）

```gdscript
func start_listening() -> void      # NPC 提问后调用
func on_voice_detected() -> void    # VAD 检测说话开始
func on_voice_ended() -> void       # VAD 检测说话结束 → 发送云端
func stop_listening() -> void       # 流程中断时
```

#### DialogueManager.gd（全局单例）

```gdscript
func start_npc_dialogue(npc_id, greeting) -> void
func on_player_response(result) -> void
func advance_dialogue(player_response) -> void
```

### 完整流程

```
NPC 提问 → TTS 播放 → VoicePipeline.start_listening()
         → VAD 检测说话 → 录制 → VAD 检测结束
         → ASR → LLM → TTS → DialogueManager 收到回复
         → DialogueBox 显示 + TTS 播放 → 继续监听
```

---

## NPC 系统

### NPCController.gd

```gdscript
@export var npc_id: String = "spark"
@export var npc_name: String = "精灵教练 Spark"
@export var greeting_zh: String
@export var greeting_en: String

func on_player_entered() -> void    # 触发对话
func get_greeting() -> String       # 根据语言返回问候语
func end_dialogue() -> void
```

### 对话流程示例

```
1. Spark: "你好！我是 Spark，你叫什么名字？"
2. 玩家: "我叫小明"
3. Spark: "小明，很高兴认识你！你几岁了？"
4. 玩家: "我十岁"
5. Spark: "太棒了！准备好开始探险了吗？"
6. 玩家: "准备好了"
7. Spark: "那我们一起进入精灵森林吧！"
```

---

## 全局状态管理

### GameManager.gd

```gdscript
# 玩家数据
var player_name: String = ""
var player_age: int = 0
var current_lang: String = "zh"

# 游戏进度
var unlocked_areas: Array[String] = ["SpiritForest"]
var lxp_score: int = 0

func set_player_info(name, age) -> void
func set_language(lang) -> void
func save_progress() -> void
func load_progress() -> bool
func reset() -> void
```

### Autoload 注册顺序

```
GameManager → HybridAPI → VoicePipeline → DialogueManager → AudioManager
```

---

## UI 组件

### DialogueBox.gd

```gdscript
func show_message(npc_name, text) -> void   # 淡入显示
func hide_message() -> void                 # 淡出隐藏
func show_voice_listening() -> void         # 显示"正在听..."
func hide_voice_listening() -> void
```

### CoachOverlay.gd

```gdscript
func fly_in_from(start_pos, end_pos, duration, callback) -> void
func show_hint(text, emotion) -> void       # 显示对话 + 表情动画
```

---

## 技术评估对比方案

### 评估维度

| 维度 | 权重 | 指标 |
|------|------|------|
| 语音交互性能 | 25% | VAD 响应延迟、总耗时、播放流畅度 |
| 跨平台能力 | 20% | Web 兼容性、移动端适配、包体大小 |
| 开发效率 | 15% | 功能完成度、代码量、调试体验 |
| AI集成复杂度 | 15% | API 调用稳定性、异步处理难度 |
| 团队适配度 | 10% | 学习曲线、社区资源、文档质量 |
| 扩展性 | 10% | 后续功能实现难度预估 |

### 决策规则

- 某轨道综合评分 ≥ 20% 领先 → 选择该轨道
- 差距 < 10% → 综合考虑团队偏好
- 差距 < 5% → 继续并行至 MVP 再决策

---

## 开发计划

### 时间线（4-5周）

| 周 | 任务 | 交付物 |
|---|------|--------|
| 1 | 项目搭建 + MainMenu | 项目骨架、精灵动画、语言选择流程 |
| 2 | SpiritForest + 玩家移动 | 场景布局、Player 控制器、NPC 触发 |
| 3 | 语音管线集成 | HybridAPI、VoicePipeline、云端对接 |
| 4 | DialogueManager + UI | DialogueBox、完整对话流程 |
| 5 | 测试 + 评估对比 | 功能验证、性能测试、评估报告 |

### 检查点

- Week 1：MainMenu 可运行，精灵飞入流畅
- Week 2：SpiritForest 可进入，玩家可移动
- Week 3：语音录制可用，云端调用成功
- Week 4：全程语音对话可用
- Week 5：评估报告产出

---

## 风险与备选方案

| 风险 | 备选方案 |
|------|----------|
| Godot VAD 支持不足 | 先用静音检测，Phase 3 优化 |
| Web 音频录制兼容性问题 | Web Audio API 插件或降级 |
| 云端 API 不稳定 | 本地缓存重试，离线提示 |