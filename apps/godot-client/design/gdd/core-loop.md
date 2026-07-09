# Core Loop GDD

**系统名称**: Core Loop (核心循环)
**版本**: 1.0
**日期**: 2026-06-24
**所属游戏**: LinguaQuest RPG (babble)
**依赖系统**: Dialogue System (对话系统), Quest System (任务系统), Assessment System (评估系统), Reward System (奖励系统)

---

## 1. 概述

核心循环是 LinguaQuest RPG 的游戏骨架，定义了从 30 秒微循环到长期进度循环的完整玩家体验节奏。所有其他系统（对话、任务、评估、奖励）都围绕核心循环展开。

核心循环的设计目标：
- **30 秒循环**: 让每次语音交互都产生可见反馈（魔法效果）
- **5-15 分钟循环**: 提供短期目标（积累星级获得 Badge）
- **会话循环**: 提供自然停止点和长期动力（奖励收集）
- **长期循环**: 提供跨会话的成长轨迹（CEFR 等级）

---

## 2. 玩家幻想

**玩家应该感觉**: "我的每一次英语表达都在产生魔法效果，积累到力量"

循环设计必须满足：
- **即时反馈**: 每次语音回答都在 1.5s 内产生视觉+音频反馈
- **可见进步**: 星级积累清晰可见，Badge 解锁有仪式感
- **节奏感**: 任务难度呈锯齿形曲线（紧张→释放→更高紧张）
- **自然停止点**: 会话结束不强制，而是 Spark 温柔建议休息

---

## 3. 详细规则

### 3.1 30 秒微循环（Moment-to-Moment）

**定义**: 单次 NPC-玩家对话回合

```
[Phase 1] NPC 发起对话（0-2s）
  - NPC 通过 TTS 语音播放问题/提示
  - 同步显示 NPC 动画（表情、动作）
  
[Phase 2] 玩家语音输入（等待触发，最长 10s）
  - VAD 检测玩家发言起止
  - 静默 > 10s 触发 Spark 提示介入
  
[Phase 3] ASR 转录 + LLM 评估（0.5-1.5s）
  - Whisper ASR 转录语音为文本
  - GPT-4o 评估准确性、流利度、词汇
  - 计算 LXP 分数
  
[Phase 4] NPC 响应（0.5-1.0s）
  - NPC TTS 播放回复（鼓励/纠正/继续）
  - 触发魔法特效（正确: 光芒绽放；错误: Spark 提示）
  
[Phase 5] 星级反馈（即时）
  - 显示 1-5 星评价
  - 累积到当前场景星级总数
  - 触发 Spark 评论（"Great!" / "Try again!"）
```

**关键参数**:
| 参数 | 默认值 | 可调范围 | 类别 |
|------|--------|---------|------|
| `npc_response_delay_ms` | 500 | 300-1000 | Feel |
| `silence_threshold_s` | 10 | 5-15 | Gate |
| `spark_intervention_max_count` | 3 | 1-5 | Gate |
| `star_per_correct_response` | 3-5 | 1-5 | Curve |

**边缘情况**:
| 场景 | 处理规则 |
|------|---------|
| ASR 空结果 | Spark 提示"I couldn't hear you clearly. Can you say it again?"，不扣星 |
| 网络延迟 > 3s | 显示加载动画，NPC 暂停等待 |
| 连续 2 次错误 | Spark 进入"示范模式"——播放正确发音让玩家跟读，跟读成功计为完成（不引入文字输入） |
| 背景噪音 > 60dB | Spark 提示"Let's find a quieter place"，暂停当前对话 |

---

### 3.2 8-12 分钟中循环（Short-Term Goal）

**定义**: 单个场景完成循环

**时长调整理由**：
- 四年级学生有意注意持续 20-25 分钟（需休息）
- 单场景控制在 8-12 分钟，确保连续 2-3 场景不超注意力窗口
- 添加"课间休息"机制：每完成场景后 Spark 建议"休息 1 分钟"，播放眼保健操动画

```
[Phase 1] 场景启动（1-2 分钟）
  - Spark 飞出介绍场景主题
  - NPC 欢迎对话（教学引导）
  - 显示场景目标："Collect stars to unlock the Badge"

[Phase 2] 任务序列（5-8 分钟）
  - 主线任务 1 → 微循环序列 → 星级累积
  - 主线任务 2 → 微循环序列 → 星级累积
  - 主线任务 3 → 微循环序列 → 星级累积

[Phase 3] 里程碑检查（即时）
  - 星级 >= threshold → 触发 Badge 解锁
  - 星级 < threshold → Spark 提示剩余星数

[Phase 4] Badge 解锁仪式（30-60s）
  - Spark 飞出宣布"Badge unlocked!"
  - Badge 动画（发光、旋转）
  - NPC 恭祝对话
  - 奖励展示（皮肤/装饰随机掉落）

[Phase 5] 课间休息（1 分钟，强制）
  - Spark 建议"休息一会儿，保护眼睛"
  - 播放眼保健操简短动画（可选）
  - 显示下次场景解锁提示
  - Spark 询问"Ready for the next adventure?"
```

**关键参数**:
| 参数 | 默认值 | 可调范围 | 类别 |
|------|--------|---------|------|
| `stars_to_unlock_badge` | 动态阈值 | 10-25 | Curve |
| `tasks_per_scene` | 3-4 | 2-6 | Gate |
| `badge_unlock_animation_s` | 30 | 15-60 | Feel |
| `scene_duration_min` | 8-12 | 5-20 | Gate |
| `break_duration_s` | 60 | 30-120 | Feel |

**边缘情况**:
| 场景 | 处理规则 |
|------|---------|
| 星级 > 20 但任务未完成 | Badge 解锁但任务可继续（可选完成） |
| 玩家跳过任务 | Spark 跟随但不强制，主线任务不可跳过 |
| 中途退出场景 | 保存当前星级，下次进入继续累积 |

---

### 3.3 会话循环（Session Loop, 20-30 分钟）

**定义**: 单次游戏会话从启动到结束

**时长调整理由**：
- 四年级学生注意力持续 20-25 分钟（生理硬约束）
- 单会话控制在 20-25 分钟，匹配注意力窗口，避免疲劳和注意力下降
- 完成 1 个场景（8-12 分钟）后即为自然停止点，不强制连续多场景
- 允许连续 2 场景（16-24 分钟），但仍不超过 30 分钟总窗口

```
[Phase 1] 会话启动（1-2 分钟）
  - MainMenu 显示
  - 玩家选择场景
  - Spark 问候对话（回顾上次进度）

[Phase 2] 场景游玩（16-24 分钟）
  - 中循环序列（1-2 个场景）
  - 每场景间强制 1 分钟课间休息
  - 每完成 2 场景强制 5 分钟大休息（Spark 建议）
  - 日常任务触发（每会话 3 个）

[Phase 3] 会话结束触发（条件触发）
  - 条件 1: 游玩时间 >= 45 分钟 → Spark 强制建议"Time for a break!"
  - 条件 2: 完成 3 场景 → Spark 建议"Great work today! Come back tomorrow"
  - 条件 3: 玩家说"I want to rest" → Spark 确认并保存
  - 条件 4: 玩家主动退出 → Spark 保存并告别

[Phase 4] 会话总结（1-2 分钟）
  - Spark 总结本次学习成果
  - 显示本次获得的星级、Badge、奖励
  - 家长控制台同步数据

[Phase 5] 会话结束
  - Spark 告别动画
  - MainMenu 返回
```

**关键参数**:
| 参数 | 默认值 | 可调范围 | 类别 |
|------|--------|---------|------|
| `max_session_length_min` | 30 | 20-30 | Gate |
| `max_scenes_per_session` | 2 | 1-2 | Gate |
| `daily_tasks_per_session` | 3 | 1-5 | Gate |
| `break_reminder_interval_min` | 15 | 10-25 | Gate |
| `auto_save_interval_min` | 5 | 3-10 | Feel |
| `short_break_duration_s` | 60 | 30-120 | Feel |
| `long_break_duration_min` | 5 | 3-10 | Feel |

**边缘情况**:
| 场景 | 处理规则 |
|------|---------|
| 网络中断 | 本地缓存会话数据，恢复后同步 |
| 强制关闭应用 | 下次启动自动恢复上次会话进度 |
| 多用户共享设备 | 通过家长控制台切换儿童账户 |

---

### 3.4 长期进度循环（Long-Term Progression）

**定义**: 跨会话的 CEFR 等级和奖励积累

```
[Phase 1] A1 阶段（第 1 章）
  - 场景: 精灵森林、咒语图书馆、彩虹花园
  - Badge: Forest Badge, Library Badge, Garden Badge
  - 词汇: 四年级上学期课标词汇（问候、颜色、数字、课堂用语、自然词汇）
  - 解锁条件: 3 Badge 全部获得
  
[Phase 2] A1→A2 升级
  - LXP 总量达到阈值（待定义）
  - CEFR 评估测试通过
  - 解锁传说级奖励（皮肤/精灵外观）
  
[Phase 3] A2 阶段（第 2 章）
  - 场景: 待设计（Phase 2）
  - 词汇: 四年级下学期课标词汇
  
[Phase 4] B1-C2 阶段（后续章节）
  - Phase 3 扩展内容
```

**关键参数**:
| 参数 | 默认值 | 可调范围 | 类别 |
|------|--------|---------|------|
| `badges_to_unlock_chapter2` | 3 | 2-5 | Curve |
| `lxp_threshold_for_cefr_upgrade` | TBD | TBD | Curve |
| `legendary_rewards_per_cefr_level` | 1 | 1-3 | Curve |

**边缘情况**:
| 场景 | 处理规则 |
|------|---------|
| 玩家快速通关 A1 | LXP 总量不足时提示"Explore more vocabulary before advancing" |
| 玩家停滞在 A1 | Spark 主动建议新任务，避免 boredom |
| CEFR 测试失败 | 不扣分，允许重新测试，提供针对性练习 |

---

## 4. 公式

**核心循环本身不定义星级计算公式**，而是委托给专门的子系统：

| 计算职责 | 权威来源 | 说明 |
|----------|----------|------|
| 单次回复星级 | `lxp-system.md` §4.5 | LXP 0-100 → 1-5 星映射 |
| Badge 解锁阈值 | `star-economy.md` §4.1 | 动态阈值 `calculate_badge_threshold(scene_id, player_avg_stars)` |
| 场景通关检查 | `star-economy.md` §4.3 | `can_unlock_badge(scene_stars, threshold)` |

**核心循环仅定义调用时机**：
```
[微循环 Phase 5] 调用 lxp-system 的星级计算，获取本次回复星级
[中循环 Phase 3] 调用 star-economy 的阈值公式，检查是否可解锁 Badge
```

**变量表**（来自 lxp-system.md）:
| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `accuracy` | float | 0-100 | 语音识别准确度（音素匹配率） |
| `fluency` | float | 0-100 | 流利度（语速、停顿次数、连贯性） |
| `vocabulary` | float | 0-100 | 词汇多样性（TTR 指数） |
| `LXP` | float | 0-100 | 加权总分（lxp-system.md §4.1） |
| `stars` | int | 1-5 | 最终星级（lxp-system.md §4.5） |

---

## 5. 边缘情况补充

### 5.1 ASR 失败处理矩阵

| ASR 结果 | 置信度 | Spark 行为 | 星级影响 |
|----------|--------|-----------|---------|
| 空结果 | - | "I couldn't hear you. Try again?" | 0 星（不计入） |
| 低置信度 | < 0.5 | "Did you say [transcription]? Try saying it clearly." | 1 星（鼓励尝试） |
| 中置信度 | 0.5-0.7 | "Good try! Let's practice [target_word] together." | 2 星（部分正确） |
| 高置信度 + 正确 | >= 0.7 | "Perfect! [target_word] unlocked!" | 3-5 星 |
| 高置信度 + 错误 | >= 0.7 | "You said [wrong_word]. The magic word is [target_word]." | 1 星（错误识别） |

### 5.2 多任务并发处理

| 场景 | 处理规则 |
|------|---------|
| 主线任务 + 日常任务触发 | 优先主线，日常任务可在主线间隙完成 |
| 两个 NPC 同时对话 | 不允许，NPC 按剧情顺序触发 |
| Spark 介入 + NPC 对话中 | Spark 暂停 NPC 动画，介入完成后恢复 |

---

## 6. 依赖关系

| 上游系统 | 提供内容 |
|----------|---------|
| Dialogue System | NPC 对话流程、TTS/ASR 管线 |
| Quest System | 任务触发、进度追踪 |
| Assessment System | LXP 计算、星级评估 |
| Reward System | Badge、奖励掉落 |

| 下游系统 | 消费内容 |
|----------|---------|
| Parent Dashboard | 会话时长、星级统计、Badge 获得 |
| Spirit Coach |介入时机判断、错误模式分析 |
| Game State Manager | 当前场景、星级累计、会话时长 |

---

## 7. 调节旋钮

| 旋钮名 | 文件位置 | 默认值 | 范围 | 类别 | 说明 |
|--------|---------|--------|------|------|------|
| `silence_threshold_s` | `assets/data/core_loop.json` | 10 | 5-15 | Gate | 静默多久触发 Spark 提示 |
| `stars_to_unlock_badge` | `assets/data/core_loop.json` | 动态(15-25) | 10-25 | Curve | Badge 解锁动态阈值 |
| `max_session_length_min` | `assets/data/core_loop.json` | 30 | 20-30 | Gate | 最大会话时长（匹配四年级注意力窗口 20-25min） |
| `npc_response_delay_ms` | `assets/data/core_loop.json` | 500 | 300-1000 | Feel | NPC 响应延迟 |
| `spark_intervention_max` | `assets/data/core_loop.json` | 3 | 1-5 | Gate | 单次会话 Spark 最多介入次数 |
| `auto_save_interval_min` | `assets/data/core_loop.json` | 5 | 3-10 | Feel | 自动保存频率 |

---

## 8. 接受标准

### 功能标准

- [ ] 30 秒循环可在 1.5s 内完成端到端响应（NPC →玩家 →NPC）
- [ ] 星级计算准确映射到 1-5 星
- [ ] Badge 解锁条件明确（动态阈值 10-25 星，基于场景难度和玩家历史）
- [ ] 会话时长限制生效（>= 30 分钟触发 Spark 告别提示）
- [ ] ASR 连续失败 2 次后 Spark 示范模式正常触发

### 体验标准

- [ ] 测试玩家（6-10 岁）理解星级累积目标
- [ ] Badge 解锁仪式有仪式感（测试玩家愿意截图分享）
- [ ] Spark 介入不打断对话沉浸感
- [ ] 会话结束自然（测试玩家愿意说"I'll come back tomorrow"）

### 性能标准

- [ ] P95 延迟 < 1.5s（VAD → ASR → LLM → TTS → Spark）
- [ ] ASR 识别率 >= 85%（儿童口音）
- [ ] 会话数据保存成功率 >= 99.9%

---

## 下一步

1. `/design-review design/gdd/core-loop.md` — 审查此 GDD
2. `/design-system lxp-system` — 定义完整 LXP 公式
3. `/design-system star-economy` — 设计星级经济平衡
4. `/consistency-check` — 检查与其他 GDD 的一致性