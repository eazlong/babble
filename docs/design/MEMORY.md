---
name: game_story_design_v2
description: 第一章完整故事设计——世界观、NPC、三场景叙事流程、词灵系统、场景桥接
metadata:
  type: project
---

游戏故事设计 v2.0 已写入 docs/design/game-story-design-v2.md。

**核心设定**：灵语大陆（Lingua Realm），"英语=魔法咒语"，玩家是灵语学院新生，Spark 是陪伴精灵。

**第一章三场景**：
1. 精灵森林 → NPC Oakley🦉 → 问候/颜色/数字 → Forest Badge
2. 咒语图书馆 → NPC Bookmark🐢 + Luna → 课堂指令/学习用品/对话 → Library Badge
3. 彩虹花园 → NPC Petalia🧚 + Sunny → 天气/动物方位/种花 → Garden Badge

**v2 关键修复**：
- NPC 角色统一：图书馆应为 Bookmark 主导（之前代码是 Luna）
- 花园应为 Petalia 主导（之前代码是 Sunny + Flora 两个角色）
- 新增场景间叙事桥接
- 新增词灵预告 + 收集册设计
- 新增通关仪式

**实现约束**：每个任务间需 NPC 过渡对话，不能跳切。所有对话需中英双语。

**关联**：[[grade4_english_curriculum]]（课标对应）、[[grade4_learning_psychology]]（儿童学习心理）
