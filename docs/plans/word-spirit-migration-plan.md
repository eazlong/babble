---
name: word-spirit-migration-plan
description: 词灵系统从CCGS迁移至LinguaQuest的实施方案
metadata:
  type: project
---

# 词灵系统迁移方案

## 概述

从CCGS迁移词灵系统至LinguaQuest，包含4个核心模块：

**CCGS词灵架构**：
- SpiritDatabase（静态数据提供者）
- SpiritCollectionManager（解锁管理器）
- KeywordMatcher（关键词匹配器）
- SpiritUnlockOverlay（解锁UI）

**LinguaQuest适配**：
- ✅ 已有：DialogueManager, SaveSystem, GameManager
- ❌ 缺少：CharacterDataSystem, KeywordMatcher, SpiritUnlockOverlay

---

## 迁移阶段

### Phase 1：数据层迁移（基础）

**目标**：词灵静态数据定义

**迁移文件**：
1. `src/core/spirit_database.gd` → `apps/godot-client/assets/scripts/core/spirit_database.gd`
2. `data/spirits/spirit_database.json` → `apps/godot-client/assets/resources/spirit_database.json`

**适配改动**：
- 路径修改：`DATABASE_PATH = "res://assets/resources/spirit_database.json"`
- 注册autoload：`project.godot`添加`SpiritDatabase`

**验证**：
- 运行游戏，检查词灵数据库加载成功（emit `database_loaded` signal）
- 查询测试：`get_spirit("spirit_sun_001")`返回正确数据

**Why**: 词灵数据是整个系统的基础，必须先迁移以支撑后续逻辑

**How to apply**: 第一步执行，确保数据层稳定后再进行Phase 2

---

### Phase 2：核心逻辑迁移

**目标**：关键词匹配 + 词灵解锁管理

**迁移文件**：
1. `src/core/keyword_matcher.gd` → `apps/godot-client/assets/scripts/core/keyword_matcher.gd`
2. `src/core/spirit_collection_manager.gd` → `apps/godot-client/assets/scripts/autoload/spirit_collection_manager.gd`

**适配改动**：
- **KeywordMatcher**: 无需改动（纯工具类，无依赖）
- **SpiritCollectionManager**:
  - 依赖注入改为LinguaQuest的SaveSystem
  - 移除CharacterDataSystem依赖（改用GameManager或SaveSystem直接存储）
  - 注册autoload

**集成点**：
- DialogueManager调用KeywordMatcher检测关键词
- DialogueManager检测到关键词后调用SpiritCollectionManager.unlock_spirit()

**Why**: 词灵解锁逻辑需要匹配器识别关键词，两个模块必须同时迁移

**How to apply**: Phase 1完成后执行，集成到DialogueManager对话流程

---

### Phase 3：UI层迁移

**目标**：词灵解锁仪式感动画

**迁移文件**：
1. `src/ui/hud/overlays/spirit_unlock_overlay.gd` → `apps/godot-client/assets/scripts/ui/spirit_unlock_overlay.gd`

**适配改动**：
- CanvasLayer分层：layer=30（与CoachOverlay同级）
- 调用方式：SpiritCollectionManager emit `spirit_unlocked` signal → SpiritUnlockOverlay监听并显示

**UI集成**：
- 解锁动画：全屏遮罩 + 词灵卡片 + 玉石绿光晕
- 3秒自动消失 + 点击提前关闭
- 稀有度视觉差异（Common绿/Rare蓝/Legendary金）

**Why**: 仪式感是词灵系统的核心体验，必须在UI层体现

**How to apply**: Phase 2完成后执行，监听SpiritCollectionManager信号

---

### Phase 4：集成测试迁移

**目标**：GUT单元测试 + 手动测试验证

**迁移文件**：
1. CCGS test文件 → `apps/godot-client/test/`（适配LinguaQuest结构）

**测试覆盖**：
- SpiritDatabase加载测试
- KeywordMatcher匹配逻辑测试
- SpiritCollectionManager解锁流程测试
- SpiritUnlockOverlay显示测试

**手动测试checklist**：
- 对话中使用"sun"词汇 → 触发"阳光"词灵解锁
- 解锁动画显示3秒后消失
- 存档保存词灵状态，重启后恢复

**Why**: 测试验证迁移正确性，防止回归错误

**How to apply**: Phase 3完成后执行，确保全流程可用

---

## 技术细节

### 数据模型对比

**CCGS**:
```gdscript
# CharacterDataSystem (state owner)
var _unlocked_spirits: Array[String]
var _usage_counts: Dictionary[String, int]
```

**LinguaQuest适配**:
```gdscript
# SaveSystem (LinguaQuest)
var game_state: Dictionary = {
  "unlocked_spirits": [],
  "spirit_usage_counts": {}
}
```

### 状态机设计（保持不变）

**SpiritDatabase**:
```
UNLOADED → LOADING → LOADED
         → ERROR
```

**SpiritCollectionManager**:
```
UNINITIALIZED → READY → LOADING_SAVE → ACTIVE
```

### 信号系统

**保留CCGS信号**：
- `spirit_unlocked(spirit_id, spirit_data)`
- `spirit_unlock_animation_finished(spirit_id)`
- `collection_updated(progress)`
- `usage_count_updated(spirit_id, new_count)`

---

## 迁移风险

### 1. CharacterDataSystem缺失

**风险**: CCGS有专门的角色数据系统，LinguaQuest缺少

**解决**: 改用SaveSystem存储词灵状态，迁移成本中等

### 2. DialogueManager集成

**风险**: LinguaQuest DialogueManager流程不同，需要插入关键词检测

**解决**: 在DialogueManager对话流程中添加关键词检测钩子

### 3. CanvasLayer层级冲突

**风险**: LinguaQuest已有CoachOverlay（layer=30）

**解决**: SpiritUnlockOverlay使用layer=30，但设计为互斥显示（解锁时暂停教练提示）

---

## 预估工作量

| Phase | 文件数 | 适配改动 | 测试 | 预估时间 |
|-------|--------|----------|------|----------|
| Phase 1 | 2 | 路径+autoload | 2个测试 | 30分钟 |
| Phase 2 | 2 | 依赖注入+集成DialogueManager | 4个测试 | 1小时 |
| Phase 3 | 1 | CanvasLayer+信号监听 | 2个测试 | 45分钟 |
| Phase 4 | 5+ | 测试迁移+手动checklist | 验证 | 30分钟 |
| **总计** | **10+** | **中等工作量** | **12+测试** | **约3小时** |

---

## 与[[parent-dashboard-mvp]]的关系

词灵系统与家长控制台MVP无冲突，属于独立游戏功能。

家长控制台可以扩展：
- 显示孩子收集的词灵数量
- 词灵稀有度统计
- 词灵收集进度报告

---

## 下一步

用户确认后，按Phase 1-4顺序执行迁移。