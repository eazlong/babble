# 游戏元素设计文档

> **基于**：游戏故事设计 v2.0（第 11-12 节）  
> **日期**：2026-06-23  
> **目标**：将故事设计转化为可实现的 Godot 游戏元素

---

## 1. 元素分类体系

| 类别 | 说明 | 文件模式 |
|------|------|---------|
| A. 环境交互元素 | 可点击的场景物体（L3） | `components/interactive_object.gd` |
| B. 彩蛋元素 | 隐藏触发器（L4） | `components/easter_egg_trigger.gd` |
| C. 复习模式 UI | 场景入口模式选择 | `ui/scene_mode_selector.tscn` |
| D. HUD 元素 | 常驻进度显示 | `ui/hud.tscn` |
| E. 词灵预览 | 入场词灵提示气泡 | `ui/spirit_preview.gd` |
| F. NPC 对话池 | L2 额外对话管理 | `components/npc_extra_dialogue.gd` |

---

## 2. 环境交互元素（L3）

### 2.1 基类：InteractiveObject

所有可交互场景物体继承此类。

```
InteractiveObject (extends Area2D)
├── CollisionShape2D
├── Sprite (ColorRect / AnimatedSprite2D)
├── Label (名称)
├── InteractionHint (Label, "点击我" / "说出...")
└── script: interactive_object.gd
```

**属性**：
- `object_id: String` — 唯一标识
- `interaction_keywords: Array[String]` — 触发关键词
- `interaction_response: Dictionary` — 响应（text_zh, text_en, effect）
- `click_count: int` — 点击次数统计
- `cooldown: float` — 冷却时间（默认 3s）

**行为**：
1. 玩家点击/靠近 → 显示 InteractionHint
2. 玩家说出关键词 → 触发响应（TTS + 动画 + 可能的词灵）
3. 冷却期间不再响应

### 2.2 精灵森林环境元素

| 元素 | object_id | 位置 | 关键词 | 效果 |
|------|-----------|------|--------|------|
| 发光蘑菇 | `glowing_mushroom` | (600, 680) | glow, shine, light | 闪烁动画 + 音效 |
| 小溪 | `stream` | (200, 750) | water, river, stream | 流水动画加速 |
| 大树 | `big_tree` | (150, 650) | tree, bird, fly | 树叶摇动 + 小鸟飞走 |
| 彩色蘑菇 | `colorful_mushroom` | (700, 690) | mushroom, colorful | 变色动画 |

### 2.3 咒语图书馆环境元素

| 元素 | object_id | 位置 | 关键词 | 效果 |
|------|-----------|------|--------|------|
| 漂浮的书本 | `floating_book` | (1100, 500) | book, read, story | 翻跟头动画 |
| 羽毛笔 | `quill` | (1400, 550) | write, pen, pencil | 自动写字动画 |
| 书架 | `bookshelf_interactive` | (900, 550) | big, small, shelf | 书本排列变化 |
| 窗户 | `window` | (1700, 400) | window, night, star | 场景光暗变化 |

### 2.4 彩虹花园环境元素

| 元素 | object_id | 位置 | 关键词 | 效果 |
|------|-----------|------|--------|------|
| 天气水晶 | `weather_crystal_interactive` | (900, 500) | weather, crystal, magic | 彩虹光芒动画 |
| 花丛 | `flower_bush` | (300, 650) | flower, bloom, beautiful | 花朵摇摆 |
| 小桥 | `small_bridge` | (600, 700) | bridge, water, cross | 水花动画 |
| 草丛 | `tall_grass` | (1200, 680) | grass, hide, animal | 小动物探头 |

---

## 3. 彩蛋元素（L4）

### 3.1 彩蛋触发器

```
EasterEggTrigger (extends Node)
├── script: easter_egg_trigger.gd
```

**属性**：
- `easter_egg_id: String`
- `trigger_condition: Dictionary` — 条件配置
- `response: Dictionary` — 触发效果

**支持的触发条件类型**：
| 类型 | 配置 | 示例 |
|------|------|------|
| `sequence` | `{words: ["red", "blue", "yellow"], ordered: false}` | 森林合唱 |
| `phrase` | `{phrase: "thank you", target_npc: "oakley"}` | Oakley 的秘密 |
| `click_count` | `{target: "spark", count: 5}` | Spark 的舞蹈 |
| `timed_silence` | `{duration: 10.0, scene: "spell_library"}` | 安静的魔法 |
| `achievement_chain` | `{achievements: ["find_all_animals"]}` | 花园交响曲 |

### 3.2 各场景彩蛋

| 场景 | 彩蛋名 | 触发条件 | 效果 |
|------|--------|---------|------|
| 森林 | 森林合唱 | 依次说 Red→Blue→Yellow（非任务） | 3 花同时发光 + Courage 词灵候选 |
| 森林 | Oakley 的秘密 | 对 Oakley 说 "Thank you" | 额外对话 + Love 词灵候选 |
| 森林 | Spark 的舞蹈 | 连续点击 Spark 5 次 | 跳舞动画 + 笑声 |
| 图书馆 | 安静的魔法 | 10 秒不说话 | Bookmark 额外对话 + Star 词灵 |
| 图书馆 | 书海漂流 | 依次点击 3 个书架 | 书本同时飞起再归位 |
| 图书馆 | Luna 的挑战 | 对话练习连续 3 句英文 | 额外 1 轮对话 + Dream 候选 |
| 花园 | 彩虹桥 | 天气修复后说 "rainbow" | 彩虹延伸动画 + Dream 词灵 |
| 花园 | 花园交响曲 | 找出所有 3 只动物 | 动物齐现 + 鸟叫 + Unicorn 候选 |
| 花园 | Petalia 的祝福 | 种完花说 "Thank you, Petalia" | 特别对话 + Love 词灵 |

---

## 4. 复习模式 UI

### 4.1 场景模式选择器

玩家点击已完成场景时弹出：

```
┌────────────────────────────────────┐
│   🌲 精灵森林                       │
│   ✅ 已完成 · 上次复习: 2 小时前     │
│                                    │
│   ┌────────────┐  ┌────────────┐   │
│   │ 📖 复习模式 │  │ 🏆 挑战模式 │   │
│   │ 轻松复习    │  │ 限时挑战    │   │
│   │ +30 LXP    │  │ +60 LXP    │   │
│   └────────────┘  └────────────┘   │
│                                    │
│   词灵发现: 3/6  🌟                │
└────────────────────────────────────┘
```

### 4.2 HUD（常驻）

```
┌──────────────────────────────────────┐
│ [名字]  ⭐ 350 LXP  🌟 徽章: 1/3    │
│ 任务: 颜色魔法 (2/3) ████████░░     │
│                          [📖 复习]  │
└──────────────────────────────────────┘
```

---

## 5. 词灵预览组件

进入场景时 Spark 提示可能遇到的词灵：

```
┌─────────────────────────────┐
│  ✨ Spark:                  │
│  "听说这里住着一只          │
│   叫 Sunshine 的小精灵      │
│   它喜欢和阳光有关的词哦！  │
│        ☀️                   │
└─────────────────────────────┘
```

---

## 6. NPC 额外对话池

每个 NPC 维护一个对话池，按点击次数/时机返回不同对话。

```
NPCExtraDialogue
├── dialogue_pool: Array[DialogueEntry]
├── current_index: int
├── context_tags: Array[String] (任务阶段、时间等)
└── get_next() → DialogueEntry
```

**DialogueEntry**：
```
{
  "id": "oakley_extra_1",
  "text_zh": "嗯……每一朵花都有自己的名字。",
  "text_en": "Hmm... Every flower has its own name.",
  "keywords": ["flower", "name"],
  "trigger_context": "color_task_before",
  "spirit_hint": "light"
}
```

---

## 7. 实现优先级

| 优先级 | 元素 | 理由 |
|--------|------|------|
| **P0** | InteractiveObject 基类 | 所有 L3 元素的基础 |
| **P0** | 精灵森林 4 个环境元素 | 第一个场景，先行验证 |
| **P1** | NPCExtraDialogue 系统 | L2 交互核心 |
| **P1** | EasterEggTrigger 基类 | L4 彩蛋基础 |
| **P1** | 复习模式 UI + 流程 | 复习功能入口 |
| **P2** | HUD | 进度可视化 |
| **P2** | SpiritPreview | 词灵预告 |
| **P2** | 图书馆 + 花园环境元素 | 复用森林模式 |

---

## 8. 新增文件清单

| 文件 | 类型 | 说明 | 状态 |
|------|------|------|------|
| `components/interactive_object.gd` | 脚本 | L3 环境交互基类 | ✅ 已实现 |
| `components/easter_egg_trigger.gd` | 脚本 | L4 彩蛋触发器 | ✅ 已实现 |
| `components/npc_extra_dialogue.gd` | 脚本 | NPC 额外对话管理 | ✅ 已实现 |
| `ui/hud.gd` | 脚本 | 常驻 HUD | ✅ 已实现 |
| `ui/spirit_preview.gd` | 脚本 | 词灵预览 | ✅ 已实现 |
| `ui/scene_mode_selector.gd` | 脚本 | 复习模式选择 | ✅ 已实现 |
| `data/interactive_objects.json` | 数据 | 所有交互物体配置 | ⏳ 待实现 |
| `data/npc_extra_dialogues.json` | 数据 | NPC 额外对话池 | ⏳ 待实现 |
| `data/easter_eggs.json` | 数据 | 彩蛋配置 | ⏳ 待实现 |

## 9. SpiritForest 场景元素（已添加到 .tscn）

| 节点名 | object_id | 位置 | 关键词 | 视觉效果 |
|--------|-----------|------|--------|---------|
| GlowingMushroom | `glowing_mushroom` | (600, 680) | glow, shine, light | glow |
| Stream | `stream` | (200, 750) | water, river, stream | color_shift |
| BigTree | `big_tree` | (150, 650) | tree, bird, fly | bounce |
| ColorfulMushroom | `colorful_mushroom` | (700, 690) | mushroom, colorful | color_shift |
| EasterEggTrigger | — | — | — | 彩蛋管理节点 |
| SpiritPreview | — | 顶部居中 | — | 词灵预览组件 |

## 10. 场景控制器集成指南

### 10.1 环境物体关键词检查

在每个场景控制器的 `_on_player_response()` 中，增加对环境物体的关键词检查：

```gdscript
func _on_player_response(text: String) -> void:
	last_player_input = text

	# ——— 新增：检查环境物体关键词 ———
	if _environment_objects:
		for obj in _environment_objects:
			var matched = obj.check_keyword_match(text)
			if matched != "":
				return  # 环境交互优先，不继续任务逻辑

	# ——— 原有任务逻辑 ———
	if name_collection_state == TaskState.IN_PROGRESS:
		# ...
```

### 10.2 NPC 额外对话集成

在场景控制器的 `_ready()` 中初始化 NPC 对话池：

```gdscript
@onready var oakley_extra_dialogue: NPCExtraDialogue = $OakleyExtraDialogue

func _ready() -> void:
	# 初始化 Oakley 额外对话
	if oakley_extra_dialogue:
		var dialogues = NPCExtraDialogue.get_oakley_dialogues()
		oakley_extra_dialogue.set_dialogues(dialogues)
```

在玩家点击 NPC 时调用：

```gdscript
func _on_oakley_npc_clicked() -> void:
	var entry = oakley_extra_dialogue.get_next_dialogue()
	var text = entry.text_zh if GameManager.current_lang == "zh" else entry.text_en
	coach_overlay.show_hint(text, "idle")
	HybridAPI.synthesize_tts(text, "oakley", GameManager.current_lang)
```

### 10.3 彩蛋触发器初始化

在场景控制器的 `_ready()` 中注册彩蛋：

```gdscript
@onready var easter_egg: EasterEggTrigger = $EasterEggTrigger

func _ready() -> void:
	# 注册森林彩蛋
	var forest_egg = EasterEggTrigger.EasterEggConfig.new()
	forest_egg.id = "forest_choir"
	forest_egg.type = "sequence"
	forest_egg.config = {"words": ["red", "blue", "yellow"], "ordered": false}
	forest_egg.reward_text_zh = "森林合唱！三朵花同时发光！"
	forest_egg.reward_text_en = "Forest Choir! All three flowers glow together!"
	forest_egg.spirit_hint = "courage"
	easter_egg.register_egg(forest_egg)
```

在 `_on_player_response()` 中调用：

```gdscript
func _on_player_response(text: String) -> void:
	easter_egg.on_player_said(text)
	# ... 其他逻辑
```

### 10.4 词灵预览

在场景进入时显示：

```gdscript
func _show_spirit_preview() -> void:
	var preview = get_node_or_null("SpiritPreview")
	if preview:
		preview.show_preview(
			"Sunshine",
			"听说这里住着一只叫 Sunshine 的小精灵，它喜欢和阳光有关的词哦！",
			"They say a little spirit named Sunshine lives here. It loves words about sunlight!",
			"☀️"
		)
```
